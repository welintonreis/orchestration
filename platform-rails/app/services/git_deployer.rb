require "open3"

class GitDeployer
  def self.call(git_stack, repo_path:)
    new(git_stack, repo_path).deploy
  end

  def initialize(stack, repo_path)
    @stack     = stack
    @repo_path = repo_path
    @compose   = File.join(repo_path.to_s, @stack.compose_file)
  end

  def deploy
    unless File.exist?(@compose)
      fail_with("Compose file not found: #{@stack.compose_file}")
      return
    end

    # CI gate: block deploy when latest pipeline has not passed.
    ci_ok, ci_msg = GitlabCiChecker.call(@stack)
    unless ci_ok
      fail_with("CI check failed — #{ci_msg}")
      Alert.create!(
        level:    "warning",
        resource: "git_deploy",
        message:  "Git stack \"#{@stack.name}\" deploy blocked: #{ci_msg}"
      )
      return
    end

    write_env_file

    pre_out, pre_ok = run_hook(@stack.pre_sync_cmd)
    unless pre_ok
      fail_with("PreSync hook failed:\n#{pre_out}")
      return
    end

    output, success = run_deploy
    output = [pre_out, output].reject(&:blank?).join("\n")

    if success
      post_out, _ = run_hook(@stack.post_sync_cmd)
      output = [output, post_out].reject(&:blank?).join("\n")
      record_success(output)
      # Reconcile: a fresh deploy should read as Synced/healthy in the UI.
      GitDriftService.call(@stack, repo_path: @repo_path) rescue nil
    else
      @stack.update!(status: "failed", last_deploy_output: output)
      record_revision(result: "failed", output: output)
      Alert.create!(
        level:    "critical",
        resource: "git_deploy",
        message:  "Git stack \"#{@stack.name}\" deploy failed"
      )
    end
  end

  private

  def record_success(output)
    @stack.update!(
      status:             "deployed",
      sync_status:        "synced",
      last_deploy_output: output,
      last_deployed_at:   Time.current
    )
    record_revision(result: "success", output: output)
  end

  # Snapshot of what was applied — normalized desired state (last-applied for
  # three-way diff) + resolved image digests, so rollback and history have a
  # concrete reference point.
  def record_revision(result:, output:)
    @stack.revisions.create!(
      sha:                @stack.last_commit_sha,
      normalized_compose: safe_normalized_compose,
      image_digests:      resolved_image_digests.to_json,
      deploy_output:      output,
      result:             result,
      deployed_at:        Time.current
    )
  rescue => e
    Rails.logger.warn("[GitDeployer] revision record failed: #{e.message}")
  end

  def safe_normalized_compose
    GitDriftService.new(@stack, repo_path: @repo_path).desired_services.to_json
  rescue
    nil
  end

  def resolved_image_digests
    client = DockerClient.new(endpoint: @stack.environment.effective_endpoint)
    client.services
          .select { |s| s.dig("Spec", "Labels", "com.docker.stack.namespace") == @stack.name }
          .each_with_object({}) do |s, acc|
            name = s.dig("Spec", "Name")
            acc[name] = s.dig("Spec", "TaskTemplate", "ContainerSpec", "Image")
          end
  rescue
    {}
  end

  # docker stack deploy / docker compose resolve .env for variable
  # interpolation from the current working directory, not the compose
  # file's directory — chdir there so GitStack#env_content takes effect.
  def run_deploy
    out, err, status = Open3.capture3(*build_command, chdir: File.dirname(@compose))
    combined = [out, err].reject(&:empty?).join("\n")
    [combined, status.success?]
  end

  # Pre/PostSync hooks: arbitrary admin-entered shell, run in the compose dir
  # (so they can see the checked-out repo + .env). Blank = skip, treated as ok.
  def run_hook(cmd)
    return ["", true] if cmd.blank?
    out, err, status = Open3.capture3("/bin/sh", "-c", cmd, chdir: File.dirname(@compose))
    combined = ["$ #{cmd}", out, err].reject(&:blank?).join("\n")
    [combined, status.success?]
  rescue => e
    ["hook error: #{e.message}", false]
  end

  def write_env_file
    return if @stack.env_content.blank?

    File.write(File.join(File.dirname(@compose), ".env"), @stack.env_content)
  end

  # Array form, not a single interpolated string — Open3.capture3 with one
  # string runs it through a shell, and @stack.name/@compose (both
  # user-supplied) weren't escaped, which was a command injection hole.
  # Array args go straight to exec, no shell involved.
  def build_command
    host = @stack.environment.effective_endpoint
    case @stack.deploy_mode
    when "swarm_stack"
      ["docker", "-H", host, "stack", "deploy", "--compose-file", @compose, "--with-registry-auth", @stack.name]
    when "compose"
      ["docker", "-H", host, "compose", "-f", @compose, "up", "-d", "--remove-orphans"]
    end
  end

  def fail_with(msg)
    @stack.update!(status: "failed", last_deploy_output: msg)
  end
end

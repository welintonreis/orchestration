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

    output, success = run_deploy

    if success
      @stack.update!(
        status:              "deployed",
        last_deploy_output:  output,
        last_deployed_at:    Time.current
      )
    else
      @stack.update!(status: "failed", last_deploy_output: output)
      Alert.create!(
        level:    "critical",
        resource: "git_deploy",
        message:  "Git stack \"#{@stack.name}\" deploy failed"
      )
    end
  end

  private

  def run_deploy
    out, err, status = Open3.capture3(*build_command)
    combined = [out, err].reject(&:empty?).join("\n")
    [combined, status.success?]
  end

  # Array form, not a single interpolated string — Open3.capture3 with one
  # string runs it through a shell, and @stack.name/@compose (both
  # user-supplied) weren't escaped, which was a command injection hole.
  # Array args go straight to exec, no shell involved.
  def build_command
    case @stack.deploy_mode
    when "swarm_stack"
      ["docker", "stack", "deploy", "--compose-file", @compose, "--with-registry-auth", @stack.name]
    when "compose"
      ["docker", "compose", "-f", @compose, "up", "-d", "--remove-orphans"]
    end
  end

  def fail_with(msg)
    @stack.update!(status: "failed", last_deploy_output: msg)
  end
end

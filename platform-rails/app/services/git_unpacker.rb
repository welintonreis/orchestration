require "open3"
require "digest"

class GitUnpacker
  # GIT_WORKSPACE_HOST_PATH, when set, is a host bind mount at the same
  # absolute path on both sides (see docker-entrypoint.sh) — required for
  # compose files with relative bind mounts to resolve correctly against
  # the real host filesystem when GitDeployer's "docker stack deploy"
  # (running in this container) talks to the daemon on the bare host.
  # Falls back to the container-local tmp dir for compose-mode/dev/yaml
  # sources that don't rely on host bind-mount paths.
  TMP_DIR = Pathname.new(ENV.fetch("GIT_WORKSPACE_HOST_PATH", Rails.root.join("tmp", "git_repos").to_s))

  def self.call(git_stack)
    new(git_stack).unpack
  end

  # Rollback support: ensure the repo, fetch the requested sha (the shallow
  # clone may not contain an older commit), hard-checkout it. Returns repo_path.
  def self.checkout(git_stack, ref)
    new(git_stack).checkout(ref)
  end

  # Keyed by id when the stack is persisted; an unsaved stack (the
  # compose-file preview/autocomplete on git_stacks/new, before the user
  # has actually created it) falls back to a digest of its repo_url so
  # repeated previews of the same repo reuse one clone instead of a fresh
  # one per keystroke.
  def self.repo_dir(git_stack)
    key = git_stack.id&.to_s || "preview-#{Digest::SHA256.hexdigest(git_stack.repo_url.to_s)[0, 16]}"
    TMP_DIR.join(key)
  end

  def initialize(stack)
    @stack    = stack
    @repo_dir = self.class.repo_dir(stack)
  end

  def unpack
    FileUtils.mkdir_p(@repo_dir)
    if @repo_dir.join(".git").exist?
      pull
    else
      clone
    end
    update_commit_sha
    @repo_dir
  end

  def checkout(ref)
    unpack
    run_git("-C", @repo_dir.to_s, "fetch", "--depth", "1", "origin", ref)
    run_git("-C", @repo_dir.to_s, "checkout", "--force", ref)
    @stack.update_columns(last_commit_sha: ref, last_pulled_at: Time.current) if @stack.persisted?
    @repo_dir
  end

  private

  def clone
    run_git("clone", "--depth", "1", "--branch", @stack.branch,
            @stack.authenticated_url, @repo_dir.to_s)
  end

  def pull
    run_git("-C", @repo_dir.to_s, "fetch", "--depth", "1", "origin", @stack.branch)
    run_git("-C", @repo_dir.to_s, "reset", "--hard", "FETCH_HEAD")
  end

  def update_commit_sha
    return unless @stack.persisted?

    sha = `git -C #{@repo_dir} rev-parse HEAD 2>/dev/null`.strip
    @stack.update_columns(last_commit_sha: sha, last_pulled_at: Time.current)
  end

  def run_git(*args)
    env = { "GIT_TERMINAL_PROMPT" => "0" }
    key_file = nil
    if @stack.auth_type == "ssh_key"
      key_file = write_ssh_key
      env["GIT_SSH_COMMAND"] = "ssh -i #{key_file} -o StrictHostKeyChecking=no"
    end
    out, err, status = Open3.capture3(env, "git", *args)
    FileUtils.rm_f(key_file) if key_file
    raise "git failed: #{err}" unless status.success?
    out
  end

  def write_ssh_key
    key_dir  = Rails.root.join("tmp", "git_keys")
    FileUtils.mkdir_p(key_dir)
    key_file = key_dir.join("#{@stack.id}.key").to_s
    File.write(key_file, @stack.ssh_key + "\n")
    File.chmod(0o600, key_file)
    key_file
  end
end

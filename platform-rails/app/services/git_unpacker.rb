require "open3"

class GitUnpacker
  TMP_DIR = Rails.root.join("tmp", "git_repos")

  def self.call(git_connection)
    new(git_connection).unpack
  end

  def initialize(connection)
    @connection = connection
    @repo_dir   = TMP_DIR.join(@connection.id.to_s)
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

  private

  def clone
    run_git("clone", "--depth", "1", "--branch", @connection.branch,
            authenticated_url, @repo_dir.to_s)
  end

  def pull
    run_git("-C", @repo_dir.to_s, "fetch", "--depth", "1", "origin", @connection.branch)
    run_git("-C", @repo_dir.to_s, "reset", "--hard", "FETCH_HEAD")
  end

  def update_commit_sha
    sha = `git -C #{@repo_dir} rev-parse HEAD 2>/dev/null`.strip
    @connection.update_columns(last_commit_sha: sha, last_pulled_at: Time.current)
  end

  def authenticated_url
    @connection.authenticated_url
  end

  def run_git(*args)
    env = { "GIT_TERMINAL_PROMPT" => "0" }
    key_file = nil
    if @connection.auth_type == "ssh_key"
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
    key_file = key_dir.join("#{@connection.id}.key").to_s
    File.write(key_file, @connection.ssh_key + "\n")
    File.chmod(0o600, key_file)
    key_file
  end
end

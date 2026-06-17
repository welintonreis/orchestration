require "open3"
require "timeout"

# Lightweight reachability check (git ls-remote, no clone) so the
# /git_connections list can show online/offline per row without the
# multi-second cost of an actual git clone (GitUnpacker).
class GitConnectionChecker
  TIMEOUT = 6

  def self.call(connection) = new(connection).online?

  def initialize(connection)
    @connection = connection
  end

  def online?
    Timeout.timeout(TIMEOUT) { run_check }
  rescue StandardError, Timeout::Error
    false
  end

  private

  def run_check
    env = { "GIT_TERMINAL_PROMPT" => "0" }
    key_file = nil
    if @connection.auth_type == "ssh_key"
      key_file = write_ssh_key
      env["GIT_SSH_COMMAND"] = "ssh -i #{key_file} -o StrictHostKeyChecking=no -o ConnectTimeout=5"
    end
    url = @connection.auth_type == "token" ? @connection.authenticated_url : @connection.repo_url
    _out, _err, status = Open3.capture3(env, "git", "ls-remote", "--exit-code", url, "HEAD")
    status.success?
  ensure
    FileUtils.rm_f(key_file) if key_file
  end

  def write_ssh_key
    dir  = Rails.root.join("tmp", "git_keys")
    FileUtils.mkdir_p(dir)
    file = dir.join("check_#{@connection.id}.key").to_s
    File.write(file, @connection.ssh_key + "\n")
    File.chmod(0o600, file)
    file
  end
end

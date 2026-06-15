require "open3"

class GitPollService
  def self.call(git_connection)
    new(git_connection).latest_sha
  end

  def initialize(connection)
    @connection = connection
  end

  def latest_sha
    env = { "GIT_TERMINAL_PROMPT" => "0" }
    url = @connection.authenticated_url
    out, _err, status = Open3.capture3(
      env,
      "git", "ls-remote", url, "refs/heads/#{@connection.branch}"
    )
    return nil unless status.success?
    out.split.first
  end
end

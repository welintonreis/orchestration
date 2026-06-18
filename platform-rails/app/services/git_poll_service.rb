require "open3"

class GitPollService
  def self.call(git_stack)
    new(git_stack).latest_sha
  end

  def initialize(stack)
    @stack = stack
  end

  def latest_sha
    env = { "GIT_TERMINAL_PROMPT" => "0" }
    url = @stack.authenticated_url
    out, _err, status = Open3.capture3(
      env,
      "git", "ls-remote", url, "refs/heads/#{@stack.branch}"
    )
    return nil unless status.success?
    out.split.first
  end
end

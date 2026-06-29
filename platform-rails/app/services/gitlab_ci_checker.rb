require "json"

# Checks that the latest GitLab CI pipeline for the stack's branch passed
# before allowing a deploy. Uses Excon (already a dependency) against the
# GitLab API v4 — no new gems needed.
#
# Returns [ok, message] where ok is true when deploy should proceed.
class GitlabCiChecker
  def self.call(stack)
    new(stack).check
  end

  def initialize(stack)
    @stack = stack
  end

  def check
    return [true, nil] unless @stack.ci_check_enabled?
    return [false, "CI check enabled but ci_gitlab_url is blank"] if @stack.ci_gitlab_url.blank?
    return [false, "CI check enabled but ci_project_id is blank"]  if @stack.ci_project_id.blank?
    return [false, "CI check enabled but ci_token_ciphertext is blank"] if @stack.ci_token_ciphertext.blank?

    pipeline = latest_pipeline
    return [false, "No pipeline found for branch #{branch}"] if pipeline.nil?

    status = pipeline["status"]
    if status == "success"
      [true, "CI pipeline ##{pipeline['id']} passed"]
    else
      [false, "CI pipeline ##{pipeline['id']} status: #{status} — deploy blocked"]
    end
  rescue => e
    [false, "CI check error: #{e.message}"]
  end

  private

  def latest_pipeline
    url     = "#{@stack.ci_gitlab_url.chomp("/")}/api/v4/projects/#{CGI.escape(@stack.ci_project_id)}/pipelines"
    params  = { ref: branch, per_page: "1", order_by: "id", sort: "desc" }
    query   = params.map { |k, v| "#{k}=#{CGI.escape(v)}" }.join("&")
    headers = { "PRIVATE-TOKEN" => @stack.ci_token_ciphertext, "Accept" => "application/json" }

    response = Excon.get("#{url}?#{query}",
      headers:         headers,
      connect_timeout: 5,
      read_timeout:    10
    )

    raise "GitLab API returned #{response.status}" unless (200..299).cover?(response.status)

    pipelines = JSON.parse(response.body)
    pipelines.first
  end

  def branch
    @stack.branch.presence || "main"
  end
end

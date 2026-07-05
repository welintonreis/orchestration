require "test_helper"

class WebhooksDeploysControllerTest < ActionDispatch::IntegrationTest
  # Machine-to-machine callers (GitHusky deploy hook, curl) send no CSRF
  # token — the regression this guards: default_protect_from_forgery 422'd
  # every webhook POST before the controller even ran.
  test "unknown token returns 404 json, not a 422 CSRF rejection" do
    post "/webhooks/definitely-not-a-token/deploy",
      headers: { "Content-Type" => "application/json" }, params: "{}"
    assert_response :not_found
    assert_equal "not found", response.parsed_body["error"]
  end

  test "known token queues a deploy and returns 202" do
    stack = git_stacks(:basic_git_stack)

    assert_enqueued_with(job: GitDeployJob, args: [ stack.id ]) do
      post "/webhooks/#{stack.webhook_token}/deploy",
        headers: { "Content-Type" => "application/json" }, params: "{}"
    end
    assert_response :accepted
    assert_equal "queued", response.parsed_body["status"]
  end
end

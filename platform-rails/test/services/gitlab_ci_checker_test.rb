require "test_helper"

class GitlabCiCheckerTest < ActiveSupport::TestCase
  def ci_stack
    git_stacks(:ci_check_stack)
  end

  def no_ci_stack
    git_stacks(:basic_git_stack)
  end

  test "returns ok when ci_check not enabled" do
    ok, msg = GitlabCiChecker.call(no_ci_stack)
    assert ok
    assert_nil msg
  end

  test "returns error when ci_gitlab_url blank" do
    stack = build_git_stack(ci_check_enabled: true, ci_gitlab_url: "", ci_project_id: "p", ci_token_ciphertext: "t")
    ok, msg = GitlabCiChecker.call(stack)
    assert_not ok
    assert_includes msg, "ci_gitlab_url"
  end

  test "returns error when ci_project_id blank" do
    stack = build_git_stack(ci_check_enabled: true, ci_gitlab_url: "https://gl.example.com", ci_project_id: "", ci_token_ciphertext: "t")
    ok, msg = GitlabCiChecker.call(stack)
    assert_not ok
    assert_includes msg, "ci_project_id"
  end

  test "returns error when ci_token blank" do
    stack = build_git_stack(ci_check_enabled: true, ci_gitlab_url: "https://gl.example.com", ci_project_id: "p", ci_token_ciphertext: "")
    ok, msg = GitlabCiChecker.call(stack)
    assert_not ok
    assert_includes msg, "ci_token_ciphertext"
  end

  test "ok=true when pipeline status is success" do
    pipelines = [{ "id" => 42, "status" => "success" }].to_json
    stub_excon(status: 200, body: pipelines) do
      ok, msg = GitlabCiChecker.call(ci_stack)
      assert ok
      assert_includes msg, "42"
    end
  end

  test "ok=false when pipeline status is failed" do
    pipelines = [{ "id" => 99, "status" => "failed" }].to_json
    stub_excon(status: 200, body: pipelines) do
      ok, msg = GitlabCiChecker.call(ci_stack)
      assert_not ok
      assert_includes msg, "failed"
    end
  end

  test "ok=false when no pipeline found (empty array)" do
    stub_excon(status: 200, body: "[]") do
      ok, msg = GitlabCiChecker.call(ci_stack)
      assert_not ok
      assert_includes msg, "No pipeline"
    end
  end

  test "ok=false when GitLab returns 401" do
    stub_excon(status: 401, body: "Unauthorized") do
      ok, msg = GitlabCiChecker.call(ci_stack)
      assert_not ok
      assert_includes msg, "401"
    end
  end

  private

  def stub_excon(status:, body:)
    Excon.defaults[:mock] = true
    Excon.stub({}, { status: status, body: body })
    yield
  ensure
    Excon.stubs.clear
    Excon.defaults[:mock] = false
  end
end

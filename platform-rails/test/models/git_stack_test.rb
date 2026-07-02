require "test_helper"

class GitStackTest < ActiveSupport::TestCase
  # Validations

  test "valid git stack" do
    stack = build_git_stack
    assert stack.valid?
  end

  test "requires name" do
    stack = build_git_stack(name: "")
    assert_not stack.valid?
    assert stack.errors[:name].any?
  end

  test "requires repo_url for git source_type" do
    stack = build_git_stack(repo_url: "")
    assert_not stack.valid?
    assert stack.errors[:repo_url].any?
  end

  test "requires yaml_content for yaml source_type" do
    stack = build_git_stack(source_type: "yaml", repo_url: nil, yaml_content: "")
    assert_not stack.valid?
    assert stack.errors[:yaml_content].any?
  end

  test "rejects invalid deploy_mode" do
    stack = build_git_stack(deploy_mode: "kubernetes")
    assert_not stack.valid?
  end

  test "rejects invalid status" do
    stack = build_git_stack(status: "running")
    assert_not stack.valid?
  end

  # to_param

  test "to_param returns uuid" do
    stack = git_stacks(:basic_git_stack)
    assert_equal stack.uuid, stack.to_param
  end

  # webhook_url

  test "webhook_url builds correct URL from base" do
    stack = git_stacks(:basic_git_stack)
    url = stack.webhook_url("https://app.example.com")
    assert_equal "https://app.example.com/webhooks/#{stack.webhook_token}/deploy", url
  end

  # auth_type / auth helpers

  test "auth_type is none when no credential and no token" do
    stack = build_git_stack
    assert_equal "none", stack.auth_type
  end

  test "auth_type is token when token_ciphertext present" do
    stack = build_git_stack(token_ciphertext: "mytoken")
    assert_equal "token", stack.auth_type
  end

  test "authenticated_url injects user/pass for token auth" do
    stack = build_git_stack(token_ciphertext: "tok", username: "git")
    url = stack.authenticated_url
    assert_includes url, "git:tok@"
  end

  test "authenticated_url returns repo_url unchanged for no auth" do
    stack = build_git_stack
    assert_equal stack.repo_url, stack.authenticated_url
  end

  # drift

  test "drift parses valid JSON" do
    stack = build_git_stack(drift_detail: '{"services": ["web"]}')
    assert_equal({ "services" => ["web"] }, stack.drift)
  end

  test "drift returns empty hash for blank drift_detail" do
    stack = build_git_stack(drift_detail: nil)
    assert_equal({}, stack.drift)
  end

  test "drift returns empty hash for invalid JSON" do
    stack = build_git_stack(drift_detail: "not json")
    assert_equal({}, stack.drift)
  end

  test "out_of_sync? true when sync_status is out_of_sync" do
    stack = git_stacks(:self_heal_stack)
    assert stack.out_of_sync?
  end

  test "out_of_sync? false when sync_status is synced" do
    stack = git_stacks(:auto_update_stack)
    assert_not stack.out_of_sync?
  end

  # within_sync_window?

  test "blank sync_window is always open" do
    stack = build_git_stack(sync_window: "")
    assert stack.within_sync_window?
  end

  test "within_sync_window? true inside configured window" do
    stack = build_git_stack(sync_window: "mon-fri 08:00-20:00")
    monday_noon = Time.zone.parse("2025-01-06 12:00:00")  # Monday
    assert stack.within_sync_window?(monday_noon)
  end

  test "within_sync_window? false outside day range" do
    stack = build_git_stack(sync_window: "mon-fri 08:00-20:00")
    saturday = Time.zone.parse("2025-01-04 12:00:00")  # Saturday
    assert_not stack.within_sync_window?(saturday)
  end

  test "within_sync_window? false outside hour range" do
    stack = build_git_stack(sync_window: "mon-fri 08:00-20:00")
    monday_midnight = Time.zone.parse("2025-01-06 01:00:00")  # Monday 1am
    assert_not stack.within_sync_window?(monday_midnight)
  end

  test "within_sync_window? true for malformed spec (safe fallback)" do
    stack = build_git_stack(sync_window: "garbage!!!")
    assert stack.within_sync_window?
  end

  # CI fields

  test "ci_check_enabled false by default" do
    stack = git_stacks(:basic_git_stack)
    assert_not stack.ci_check_enabled?
  end

  test "ci_check_enabled true when set" do
    stack = git_stacks(:ci_check_stack)
    assert stack.ci_check_enabled?
    assert_equal "https://gitlab.example.com", stack.ci_gitlab_url
    assert_equal "redhusky/ci-app", stack.ci_project_id
    assert_equal "glpat-test-token", stack.ci_token
  end

  # Callbacks: uuid + webhook_token on create

  test "before_create generates uuid" do
    stack = build_git_stack(uuid: nil)
    stack.save!
    assert stack.uuid.present?
  end

  test "before_create generates webhook_token" do
    stack = build_git_stack(webhook_token: nil)
    stack.save!
    assert stack.webhook_token.present?
    assert_equal 64, stack.webhook_token.length
  end

  # Fleet deploy target

  test "fleet? is false without a target_group" do
    assert_not build_git_stack.fleet?
  end

  test "fleet? is true once a target_group is set" do
    group = EnvironmentGroup.create!(name: "fleet-group-#{SecureRandom.hex(4)}")
    assert build_git_stack(target_group: group).fleet?
  end
end

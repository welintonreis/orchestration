require "test_helper"

class AuditLogTest < ActiveSupport::TestCase
  test "record creates an audit log entry" do
    user = users(:admin_user)
    assert_difference "AuditLog.count", 1 do
      AuditLog.record(user: user, action: "deploy", target_type: "GitStack",
                      target_id: 42, metadata: { sha: "abc" }, ip_address: "1.2.3.4")
    end
  end

  test "record returns the created record" do
    user = users(:admin_user)
    log = AuditLog.record(user: user, action: "test_action")
    assert_equal "test_action", log.action
    assert_equal user, log.user
  end

  test "record stores metadata" do
    user = users(:admin_user)
    log = AuditLog.record(user: user, action: "redeploy", metadata: { reason: "drift" })
    assert_equal({ "reason" => "drift" }, log.metadata)
  end

  test "record stores target_id as string" do
    user = users(:admin_user)
    log = AuditLog.record(user: user, action: "remove", target_type: "Container", target_id: 99)
    assert_equal "99", log.target_id
  end

  test "recent scope returns newest first" do
    logs = AuditLog.recent
    assert logs.first.created_at >= logs.last.created_at
  end

  test "record silently ignores errors" do
    assert_nothing_raised do
      # Pass an invalid user (nil) to trigger a DB error — should not raise.
      AuditLog.record(user: nil, action: "crash")
    end
  end

  test "belongs_to user" do
    log = audit_logs(:deploy_action)
    assert_equal users(:admin_user), log.user
  end
end

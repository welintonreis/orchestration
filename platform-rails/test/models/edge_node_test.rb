require "test_helper"

class EdgeNodeTest < ActiveSupport::TestCase
  test "enroll! creates a node, its environment, and returns a raw token" do
    node, raw_token = EdgeNode.enroll!(name: "box1")

    assert node.persisted?
    assert raw_token.present?
    assert_equal 64, raw_token.length # SecureRandom.hex(32)
    assert_equal "edge", node.environment.endpoint_type
    assert_equal "edge://#{node.uuid}", node.environment.endpoint
    assert_not_equal raw_token, node.token_digest
  end

  test "authenticate finds the node for a valid raw token" do
    node, raw_token = EdgeNode.enroll!(name: "box2")
    assert_equal node, EdgeNode.authenticate(raw_token)
  end

  test "authenticate returns nil for a wrong token" do
    EdgeNode.enroll!(name: "box3")
    assert_nil EdgeNode.authenticate("not-the-token")
  end

  test "authenticate returns nil for a revoked node" do
    node, raw_token = EdgeNode.enroll!(name: "box4")
    node.revoke!
    assert_nil EdgeNode.authenticate(raw_token)
  end

  test "status reflects revoked/online/offline" do
    node, _ = EdgeNode.enroll!(name: "box5")
    assert_equal "offline", node.status

    node.touch_heartbeat!
    assert_equal "online", node.status

    node.revoke!
    assert_equal "revoked", node.status
  end

  test "touch_heartbeat! updates last_seen_at and agent metadata" do
    node, _ = EdgeNode.enroll!(name: "box6")
    node.touch_heartbeat!(agent_version: "1.0.0", os: "linux", arch: "amd64")
    node.reload
    assert node.last_seen_at.present?
    assert_equal "1.0.0", node.agent_version
    assert_equal "linux", node.os
    assert_equal "amd64", node.arch
  end
end

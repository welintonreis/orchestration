require "test_helper"

class EdgeCommandTest < ActiveSupport::TestCase
  def node
    @node ||= EdgeNode.enroll!(name: "cmd-node").first
  end

  test "enqueue! creates a pending command with default TTL" do
    cmd = EdgeCommand.enqueue!(edge_node: node, kind: "open_stream", payload: { session_id: "abc" })
    assert_equal "pending", cmd.status
    assert_equal({ "session_id" => "abc" }, cmd.payload_data)
    assert cmd.expires_at > 23.hours.from_now
  end

  test "pending scope excludes acked and expired commands" do
    pending = EdgeCommand.enqueue!(edge_node: node, kind: "open_stream")
    acked   = EdgeCommand.enqueue!(edge_node: node, kind: "open_stream")
    acked.ack!(ok: true)

    assert_includes node.edge_commands.pending, pending
    assert_not_includes node.edge_commands.pending, acked
  end

  test "pending scope excludes commands past their expiry" do
    cmd = EdgeCommand.enqueue!(edge_node: node, kind: "open_stream", ttl: -1.minute)
    assert_not_includes node.edge_commands.pending, cmd
  end

  test "ack! stores the result and flips status" do
    cmd = EdgeCommand.enqueue!(edge_node: node, kind: "open_stream")
    cmd.ack!(ok: true, port: 4000)
    assert_equal "acked", cmd.status
    assert_equal({ "ok" => true, "port" => 4000 }, cmd.result_data)
  end

  test "expire_stale! flips expired pending commands and alerts" do
    cmd = EdgeCommand.enqueue!(edge_node: node, kind: "open_stream", ttl: -1.minute)
    assert_difference "Alert.count", 1 do
      EdgeCommand.expire_stale!
    end
    assert_equal "expired", cmd.reload.status
  end

  test "expire_stale! leaves fresh pending commands alone" do
    cmd = EdgeCommand.enqueue!(edge_node: node, kind: "open_stream")
    assert_no_difference "Alert.count" do
      EdgeCommand.expire_stale!
    end
    assert_equal "pending", cmd.reload.status
  end
end

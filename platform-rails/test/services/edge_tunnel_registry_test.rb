require "test_helper"

# Only the parts of EdgeTunnelRegistry that don't require a live WS peer are
# unit-tested here (proxy allocation, online? bookkeeping). The actual
# handshake/framing/bridging path is exercised end-to-end with a real agent
# process against a real server — see docs/specs/feature-edge-compute.md's
# manual verification notes; a mock WS driver here would just prove the
# mock behaves as configured, not that the tunnel works.
class EdgeTunnelRegistryTest < ActiveSupport::TestCase
  def node
    @node ||= EdgeNode.enroll!(name: "tunnel-test-node").first
  end

  test "proxy_endpoint_for opens a real listening local TCP port" do
    endpoint = EdgeTunnelRegistry.instance.proxy_endpoint_for(node)
    assert_match %r{\Atcp://127\.0\.0\.1:\d+\z}, endpoint

    port = endpoint[%r{:(\d+)\z}, 1].to_i
    conn = TCPSocket.new("127.0.0.1", port)
    assert conn.is_a?(TCPSocket)
  ensure
    conn&.close
  end

  test "proxy_endpoint_for returns the same address on repeated calls for the same node" do
    first  = EdgeTunnelRegistry.instance.proxy_endpoint_for(node)
    second = EdgeTunnelRegistry.instance.proxy_endpoint_for(node)
    assert_equal first, second
  end

  test "different nodes get different proxy addresses" do
    node_b = EdgeNode.enroll!(name: "tunnel-test-node-b").first
    assert_not_equal EdgeTunnelRegistry.instance.proxy_endpoint_for(node),
                      EdgeTunnelRegistry.instance.proxy_endpoint_for(node_b)
  end

  test "online? is false with no control channel registered" do
    assert_not EdgeTunnelRegistry.instance.online?(node)
  end
end

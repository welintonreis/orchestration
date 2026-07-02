require "test_helper"

class Api::EdgeControllerTest < ActionDispatch::IntegrationTest
  test "enroll with a valid token creates a node and returns a permanent token" do
    token = EdgeEnrollmentToken.generate(node_name: "box1")

    assert_difference "EdgeNode.count", 1 do
      post api_edge_enroll_url, params: { enrollment_token: token, agent_version: "1.0.0", os: "linux", arch: "amd64" }
    end

    assert_response :created
    body = JSON.parse(response.body)
    assert body["node_token"].present?
    assert body["node_id"].present?

    node = EdgeNode.last
    assert_equal "box1", node.name
    assert_equal "1.0.0", node.agent_version
    assert node.online?
  end

  test "enroll rejects an invalid token" do
    post api_edge_enroll_url, params: { enrollment_token: "garbage" }
    assert_response :unauthorized
  end

  test "enroll rejects a replayed token" do
    token = EdgeEnrollmentToken.generate(node_name: "box1")
    post api_edge_enroll_url, params: { enrollment_token: token }
    assert_response :created

    post api_edge_enroll_url, params: { enrollment_token: token }
    assert_response :conflict
  end

  test "heartbeat without a token is rejected" do
    post api_edge_heartbeat_url
    assert_response :unauthorized
  end

  test "heartbeat with a bad token is rejected" do
    post api_edge_heartbeat_url, headers: { "Authorization" => "Bearer nope" }
    assert_response :unauthorized
  end

  test "heartbeat updates last_seen_at and returns pending commands" do
    node, raw_token = EdgeNode.enroll!(name: "box2")
    cmd = EdgeCommand.enqueue!(edge_node: node, kind: "open_stream", payload: { session_id: "s1" })

    post api_edge_heartbeat_url, headers: { "Authorization" => "Bearer #{raw_token}" }
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal 1, body["commands"].size
    assert_equal cmd.id, body["commands"].first["id"]
    assert_equal "open_stream", body["commands"].first["kind"]
    assert_equal({ "session_id" => "s1" }, body["commands"].first["payload"])
    assert node.reload.online?
  end

  test "heartbeat with metrics records a HostMetric tied to the node" do
    node, raw_token = EdgeNode.enroll!(name: "box3")
    metrics = { cpu_percent: 10, ram_percent: 20, disk_percent: 30, swap_percent: 0, load_1m: 0.1, load_5m: 0.2, load_15m: 0.3 }

    assert_difference "HostMetric.count", 1 do
      post api_edge_heartbeat_url, headers: { "Authorization" => "Bearer #{raw_token}" }, params: { metrics: metrics }
    end

    hm = HostMetric.last
    assert_equal node, hm.edge_node
    assert_equal 10.0, hm.cpu_percent
  end

  test "heartbeat with high metrics creates an alert" do
    node, raw_token = EdgeNode.enroll!(name: "box4")
    metrics = { cpu_percent: 99, ram_percent: 20, disk_percent: 30, swap_percent: 0, load_1m: 0.1, load_5m: 0.2, load_15m: 0.3 }

    assert_difference "Alert.count", 1 do
      post api_edge_heartbeat_url, headers: { "Authorization" => "Bearer #{raw_token}" }, params: { metrics: metrics }
    end
  end

  test "revoked node cannot heartbeat" do
    node, raw_token = EdgeNode.enroll!(name: "box5")
    node.revoke!

    post api_edge_heartbeat_url, headers: { "Authorization" => "Bearer #{raw_token}" }
    assert_response :unauthorized
  end

  test "ack marks a command as acked with a result" do
    node, raw_token = EdgeNode.enroll!(name: "box6")
    cmd = EdgeCommand.enqueue!(edge_node: node, kind: "open_stream")

    post api_edge_command_ack_url(cmd.id), headers: { "Authorization" => "Bearer #{raw_token}" }, params: { result: { ok: true } }
    assert_response :success
    assert_equal "acked", cmd.reload.status
    assert_equal({ "ok" => "true" }, cmd.result_data)
  end

  test "ack for another node's command is not found" do
    _node_a, token_a = EdgeNode.enroll!(name: "boxA")
    node_b, _token_b = EdgeNode.enroll!(name: "boxB")
    cmd = EdgeCommand.enqueue!(edge_node: node_b, kind: "open_stream")

    post api_edge_command_ack_url(cmd.id), headers: { "Authorization" => "Bearer #{token_a}" }
    assert_response :not_found
  end
end

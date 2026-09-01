require "test_helper"

class Swarm::NodesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:admin_user) }

  test "index renders the shell without touching the socket" do
    with_docker_client(fake_docker(nodes: :dead)) do
      get swarm_nodes_url
      assert_response :success
      assert_select "turbo-frame#nodes-content[src=?]", rows_swarm_nodes_path
      assert_select "[aria-busy='true']"
    end
  end

  test "rows renders the node table" do
    client = fake_docker(nodes: [ {
      "ID" => "n1", "Spec" => { "Role" => "manager", "Availability" => "active" },
      "Status" => { "State" => "ready", "Addr" => "10.0.0.1" },
      "Description" => { "Hostname" => "lab-01", "Engine" => { "EngineVersion" => "27.0" } },
      "ManagerStatus" => { "Leader" => true }
    } ])
    with_docker_client(client) do
      get rows_swarm_nodes_url
      assert_response :success
      assert_select "turbo-frame#nodes-content[src]", false
      assert_select "body", text: /lab-01/
    end
  end

  test "rows survives an unreachable daemon" do
    with_docker_client(fake_docker(nodes: :dead)) do
      get rows_swarm_nodes_url
      assert_response :success
    end
  end
end

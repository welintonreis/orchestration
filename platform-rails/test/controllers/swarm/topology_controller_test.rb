require "test_helper"

class Swarm::TopologyControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:admin_user) }

  test "index renders the shell without touching the socket" do
    with_docker_client(fake_docker(nodes: :dead, services: :dead, tasks: :dead)) do
      get swarm_topology_url
      assert_response :success
      assert_select "turbo-frame#topology-content[src=?]", rows_swarm_topology_path
      assert_select "[aria-busy='true']"
    end
  end

  # metrics-refresh reloads the frame by pointing it back at this URL, so a
  # turbo-frame GET of #index must answer with content, never the skeleton.
  test "index answers a turbo-frame request with the real content" do
    with_docker_client(fake_docker(nodes: [], services: [], tasks: [])) do
      get swarm_topology_url, headers: { "Turbo-Frame" => "topology-content" }
      assert_response :success
      assert_select "turbo-frame#topology-content[src]", false
    end
  end

  test "rows renders the topology" do
    client = fake_docker(
      nodes: [ { "ID" => "n1", "Spec" => { "Role" => "manager", "Availability" => "active" },
                 "Status" => { "State" => "ready" }, "Description" => { "Hostname" => "lab-01" } } ],
      services: [], tasks: []
    )
    with_docker_client(client) do
      get rows_swarm_topology_url
      assert_response :success
      assert_select "turbo-frame#topology-content"
      assert_select "body", text: /lab-01/
    end
  end

  test "rows survives an unreachable daemon" do
    with_docker_client(fake_docker(nodes: :dead, services: :dead, tasks: :dead)) do
      get rows_swarm_topology_url
      assert_response :success
    end
  end
end

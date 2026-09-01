require "test_helper"

class Swarm::DashboardControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:admin_user) }

  test "index renders the shell without touching the socket" do
    with_docker_client(fake_docker(swarm_info: :dead, nodes: :dead, info: :dead)) do
      get swarm_url
      assert_response :success
      assert_select "turbo-frame#swarm-content[src=?]", rows_swarm_path
      assert_select "[aria-busy='true']"
    end
  end

  # SwarmGuard has to keep redirecting from the shell; if it only ran on #rows
  # a non-swarm environment would sit on a skeleton forever.
  test "index still redirects when the environment has no swarm" do
    with_docker_client(fake_docker(swarm: false)) do
      get swarm_url
      assert_redirected_to root_url
    end
  end

  test "rows renders the cluster overview" do
    client = fake_docker(
      swarm_info: { "ID" => "abc123", "CreatedAt" => "2026-01-01T00:00:00Z", "UpdatedAt" => "2026-01-02T00:00:00Z", "Spec" => {} },
      nodes: [ { "ID" => "n1", "Spec" => { "Role" => "manager" }, "Status" => { "State" => "ready" }, "Description" => { "Hostname" => "lab-01" } } ],
      info: { "ServerVersion" => "27.0", "NCPU" => 4, "MemTotal" => 1024 }
    )
    with_docker_client(client) do
      get rows_swarm_url
      assert_response :success
      assert_select "turbo-frame#swarm-content"
      assert_select "turbo-frame#swarm-content[src]", false
      assert_select "body", text: /lab-01/
    end
  end

  test "rows survives an unreachable daemon" do
    with_docker_client(fake_docker(swarm_info: :dead, nodes: :dead, info: :dead)) do
      get rows_swarm_url
      assert_response :success
    end
  end
end

require "test_helper"

class Swarm::PoliciesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:admin_user) }

  test "index renders the shell without touching the socket" do
    with_docker_client(fake_docker(services: :dead, nodes: :dead)) do
      get swarm_policies_url
      assert_response :success
      assert_select "turbo-frame#policies-content[src=?]", rows_swarm_policies_path
      assert_select "[aria-busy='true']"
    end
  end

  test "rows renders the placement rules" do
    client = fake_docker(
      services: [ { "Spec" => { "Name" => "web", "TaskTemplate" => { "Placement" => { "Constraints" => [ "node.role==manager" ] } } } } ],
      nodes: [ { "Spec" => { "Labels" => { "tier" => "edge" } } } ]
    )
    with_docker_client(client) do
      get rows_swarm_policies_url
      assert_response :success
      assert_select "turbo-frame#policies-content[src]", false
      assert_select "body", text: /node.role==manager/
    end
  end

  test "rows survives an unreachable daemon" do
    with_docker_client(fake_docker(services: :dead, nodes: :dead)) do
      get rows_swarm_policies_url
      assert_response :success
    end
  end
end

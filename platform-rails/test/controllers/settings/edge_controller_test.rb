require "test_helper"

class Settings::EdgeControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:admin_user)
  end

  test "GET index requires admin role" do
    sign_in users(:readonly_user)
    get settings_edge_url
    assert_response :redirect
  end

  test "GET index renders for admin and lists nodes" do
    EdgeNode.enroll!(name: "box1")
    get settings_edge_url
    assert_response :success
    assert_select "td", text: "box1"
  end

  test "POST generate_enrollment stashes the docker run command in flash" do
    post settings_edge_generate_enrollment_url, params: { node_name: "new-box" }
    assert_redirected_to settings_edge_url
    follow_redirect!
    assert_match "EDGE_ENROLLMENT_TOKEN=", response.body
  end

  test "POST generate_enrollment requires a node name" do
    post settings_edge_generate_enrollment_url, params: { node_name: "" }
    assert_redirected_to settings_edge_url
    assert_equal "Nome do node é obrigatório.", flash[:alert]
  end

  test "POST revoke_node revokes the node" do
    node, _token = EdgeNode.enroll!(name: "box2")
    post settings_edge_revoke_node_url(node), params: {}
    assert_redirected_to settings_edge_url
    assert node.reload.revoked?
  end

  test "POST regenerate_key rotates the edge key" do
    old_key = EdgeEnrollmentToken.edge_key
    post settings_edge_regenerate_key_url
    assert_redirected_to settings_edge_url
    assert_not_equal old_key, EdgeEnrollmentToken.edge_key
  end
end

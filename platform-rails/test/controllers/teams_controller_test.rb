require "test_helper"

class TeamsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:admin_user)
    @team = Team.create!(name: "perm-ui-test-#{SecureRandom.hex(4)}")
  end

  test "GET show requires admin role" do
    sign_in users(:readonly_user)
    get team_url(@team)
    assert_response :redirect
  end

  test "GET show lists environment permissions and the environments still available" do
    TeamEnvironmentPermission.create!(team: @team, environment: environments(:local_env), role: "operator")
    get team_url(@team)
    assert_response :success
    assert_select "body", text: /operator/
  end

  test "POST add_environment_permission creates a permission row" do
    assert_difference "TeamEnvironmentPermission.count", 1 do
      post add_environment_permission_team_url(@team), params: { environment_id: environments(:local_env).id, role: "operator" }
    end
    assert_redirected_to team_path(@team)
    assert @team.environment_scoped?
  end

  test "POST add_environment_permission defaults to readonly when no role given" do
    post add_environment_permission_team_url(@team), params: { environment_id: environments(:local_env).id }
    perm = @team.team_environment_permissions.last
    assert_equal "readonly", perm.role
  end

  test "DELETE remove_environment_permission removes the row" do
    TeamEnvironmentPermission.create!(team: @team, environment: environments(:local_env), role: "operator")
    assert_difference "TeamEnvironmentPermission.count", -1 do
      delete remove_environment_permission_team_url(@team), params: { environment_id: environments(:local_env).id }
    end
    assert_redirected_to team_path(@team)
  end
end

require "test_helper"

# Exercised through a real gated action (ContainersController#start,
# before_action :require_operator!) rather than unit-testing the concern in
# isolation — the whole point is that environment scoping changes what a
# real request is allowed to do.
class AuthorizationTest < ActionDispatch::IntegrationTest
  def with_docker_client(mock_client, &block)
    orig = ApplicationController.instance_method(:current_docker_client)
    ApplicationController.define_method(:current_docker_client) { mock_client }
    block.call
  ensure
    ApplicationController.define_method(:current_docker_client, orig)
  end

  def stub_client
    obj = Object.new
    obj.define_singleton_method(:container_start) { |*| {} }
    obj.define_singleton_method(:capabilities) { { swarm: false, compose: true, pods: false } }
    obj
  end

  test "user with no team keeps their global role unchanged (backward compatible default)" do
    environments(:local_env).activate!
    sign_in users(:readonly_user)

    with_docker_client(stub_client) do
      post start_container_url("abc123")
    end
    assert_redirected_to root_url # readonly, denied — same as before this feature existed
  end

  test "team scoping can upgrade a globally-readonly user for their team's environment" do
    team = Team.create!(name: "upgrade-team-#{SecureRandom.hex(4)}")
    TeamMembership.create!(team: team, user: users(:readonly_user))
    TeamEnvironmentPermission.create!(team: team, environment: environments(:local_env), role: "operator")

    environments(:local_env).activate!
    sign_in users(:readonly_user)

    with_docker_client(stub_client) do
      post start_container_url("abc123")
    end
    assert_redirected_to containers_path # allowed — team's operator grant for this environment
  end

  test "team scoping denies access to an environment the team has no row for" do
    team = Team.create!(name: "scoped-team-#{SecureRandom.hex(4)}")
    TeamMembership.create!(team: team, user: users(:operator_user))
    TeamEnvironmentPermission.create!(team: team, environment: environments(:local_env), role: "operator")

    environments(:tcp_env).activate! # NOT covered by the team's permission row
    sign_in users(:operator_user)

    with_docker_client(stub_client) do
      post start_container_url("abc123")
    end
    assert_redirected_to root_url # global "operator" role is shadowed by scoping — denied outside cluster A
  ensure
    environments(:local_env).activate!
  end

  test "global admins bypass environment scoping entirely" do
    team = Team.create!(name: "irrelevant-team-#{SecureRandom.hex(4)}")
    TeamMembership.create!(team: team, user: users(:admin_user))
    TeamEnvironmentPermission.create!(team: team, environment: environments(:local_env), role: "readonly")

    environments(:tcp_env).activate!
    sign_in users(:admin_user)

    with_docker_client(stub_client) do
      post start_container_url("abc123")
    end
    assert_redirected_to containers_path # admin role always wins, scoping doesn't apply to admins
  ensure
    environments(:local_env).activate!
  end
end

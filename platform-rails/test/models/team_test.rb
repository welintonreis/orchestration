require "test_helper"

class TeamTest < ActiveSupport::TestCase
  test "environment_scoped? is false with no permission rows" do
    team = Team.create!(name: "unscoped-team-#{SecureRandom.hex(4)}")
    assert_not team.environment_scoped?
  end

  test "environment_scoped? is true once any permission row exists" do
    team = Team.create!(name: "scoped-team-#{SecureRandom.hex(4)}")
    TeamEnvironmentPermission.create!(team: team, environment: environments(:local_env), role: "operator")
    assert team.environment_scoped?
  end
end

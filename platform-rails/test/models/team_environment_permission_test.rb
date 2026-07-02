require "test_helper"

class TeamEnvironmentPermissionTest < ActiveSupport::TestCase
  def team
    @team ||= Team.create!(name: "team-perm-test-#{SecureRandom.hex(4)}")
  end

  test "valid with a recognized role" do
    perm = TeamEnvironmentPermission.new(team: team, environment: environments(:local_env), role: "operator")
    assert perm.valid?
  end

  test "rejects an unrecognized role" do
    perm = TeamEnvironmentPermission.new(team: team, environment: environments(:local_env), role: "superadmin")
    assert_not perm.valid?
  end

  test "rejects a duplicate team+environment pair" do
    TeamEnvironmentPermission.create!(team: team, environment: environments(:local_env), role: "readonly")
    dup = TeamEnvironmentPermission.new(team: team, environment: environments(:local_env), role: "operator")
    assert_not dup.valid?
  end

  test "allows the same team scoped to a different environment" do
    TeamEnvironmentPermission.create!(team: team, environment: environments(:local_env), role: "readonly")
    other = TeamEnvironmentPermission.new(team: team, environment: environments(:tcp_env), role: "operator")
    assert other.valid?
  end
end

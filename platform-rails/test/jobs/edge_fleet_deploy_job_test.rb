require "test_helper"

class EdgeFleetDeployJobTest < ActiveSupport::TestCase
  def build_group_with_envs(names)
    group = EnvironmentGroup.create!(name: "fleet-#{SecureRandom.hex(4)}")
    envs = names.map do |n|
      env = Environment.create!(name: "fleet-env-#{n}-#{SecureRandom.hex(4)}", endpoint_type: "unix", endpoint: "unix:///var/run/docker.sock")
      EnvironmentGroupMembership.create!(environment_group: group, environment: env)
      env
    end
    [group, envs]
  end

  def fleet_stack(group)
    stack = build_git_stack(target_group: group)
    stack.save!
    stack
  end

  test "does nothing when the stack has no target_group" do
    stack = build_git_stack
    stack.save!
    unpacker_called = false
    with_stub(GitUnpacker, :call, ->(*) { unpacker_called = true; "/tmp/repo" }) do
      EdgeFleetDeployJob.perform_now(stack.id)
    end
    refute unpacker_called
  end

  test "deploys to every environment in the group and marks deployed when all succeed" do
    group, envs = build_group_with_envs(%w[a b])
    stack = fleet_stack(group)

    seen_environments = []
    deployer_stub = lambda do |s, _opts|
      seen_environments << s.environment.name
      s.update!(status: "deployed", last_deploy_output: "ok on #{s.environment.name}")
    end

    with_stub(GitUnpacker, :call, "/tmp/repo") do
      with_stub(GitDeployer, :call, deployer_stub) do
        EdgeFleetDeployJob.perform_now(stack.id)
      end
    end

    assert_equal envs.map(&:name).sort, seen_environments.sort
    stack.reload
    assert_equal "deployed", stack.status
    envs.each { |e| assert_includes stack.last_deploy_output, e.name }
  end

  test "marks failed when any member fails, but still deploys the rest" do
    group, envs = build_group_with_envs(%w[good bad])
    stack = fleet_stack(group)

    deployer_stub = lambda do |s, _opts|
      if s.environment.name.include?("bad")
        s.update!(status: "failed", last_deploy_output: "boom")
      else
        s.update!(status: "deployed", last_deploy_output: "ok")
      end
    end

    with_stub(GitUnpacker, :call, "/tmp/repo") do
      with_stub(GitDeployer, :call, deployer_stub) do
        EdgeFleetDeployJob.perform_now(stack.id)
      end
    end

    stack.reload
    assert_equal "failed", stack.status
    assert_includes stack.last_deploy_output, "boom"
    assert_includes stack.last_deploy_output, "ok"
  end

  test "does not mutate the stack's persisted environment_id" do
    group, _envs = build_group_with_envs(%w[x y])
    stack = fleet_stack(group)
    original_environment_id = stack.environment_id

    with_stub(GitUnpacker, :call, "/tmp/repo") do
      with_stub(GitDeployer, :call, ->(s, _opts) { s.update!(status: "deployed") }) do
        EdgeFleetDeployJob.perform_now(stack.id)
      end
    end

    assert_equal original_environment_id, stack.reload.environment_id
  end
end

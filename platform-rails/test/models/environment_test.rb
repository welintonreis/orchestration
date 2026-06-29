require "test_helper"

class EnvironmentTest < ActiveSupport::TestCase
  test "valid unix environment" do
    env = Environment.new(name: "test", endpoint_type: "unix", endpoint: "unix:///var/run/docker.sock")
    assert env.valid?
  end

  test "valid tcp environment" do
    env = Environment.new(name: "remote-new", endpoint_type: "tcp", endpoint: "tcp://10.0.0.1:2376")
    assert env.valid?
  end

  test "requires name" do
    env = Environment.new(endpoint_type: "unix", endpoint: "unix:///var/run/docker.sock")
    assert_not env.valid?
    assert env.errors[:name].any?
  end

  test "name must be unique" do
    existing = environments(:local_env)
    env = Environment.new(name: existing.name, endpoint_type: "unix", endpoint: "unix:///var/run/docker.sock")
    assert_not env.valid?
  end

  test "rejects invalid endpoint format" do
    env = Environment.new(name: "bad", endpoint_type: "unix", endpoint: "localhost:2376")
    assert_not env.valid?
    assert env.errors[:endpoint].any?
  end

  test "unix? returns true for unix socket" do
    assert environments(:local_env).unix?
    assert_not environments(:tcp_env).unix?
  end

  test "tcp? returns true for tcp endpoint" do
    assert environments(:tcp_env).tcp?
    assert_not environments(:local_env).tcp?
  end

  test "activate! sets this env active and deactivates others" do
    local = environments(:local_env)
    remote = environments(:tcp_env)
    assert local.active?
    remote.activate!
    assert remote.reload.active?
    assert_not local.reload.active?
  end

  test "active_env scope returns first active environment" do
    assert_equal environments(:local_env), Environment.active_env
  end
end

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

  test "valid edge environment" do
    env = Environment.new(name: "edge/box1", endpoint_type: "edge", endpoint: "edge://11111111-1111-1111-1111-111111111111")
    assert env.valid?
    assert env.edge?
  end

  test "effective_endpoint passes through unix/tcp endpoints unchanged" do
    assert_equal environments(:local_env).endpoint, environments(:local_env).effective_endpoint
    assert_equal environments(:tcp_env).endpoint, environments(:tcp_env).effective_endpoint
  end

  test "valid kubernetes environment mirrors kube_api_url into endpoint" do
    env = Environment.new(name: "k3s-local", endpoint_type: "kubernetes", kube_api_url: "https://127.0.0.1:6443")
    assert env.valid?
    assert env.kubernetes?
    assert_equal "https://127.0.0.1:6443", env.endpoint
  end

  test "kubernetes environment requires kube_api_url" do
    env = Environment.new(name: "k3s-local", endpoint_type: "kubernetes")
    assert_not env.valid?
    assert env.errors[:kube_api_url].any?
  end

  test "kube_token_ciphertext is encrypted at rest" do
    env = Environment.create!(name: "k3s-encrypted", endpoint_type: "kubernetes", kube_api_url: "https://127.0.0.1:6443", kube_token_ciphertext: "super-secret-token")
    raw = Environment.connection.select_value("SELECT kube_token_ciphertext FROM environments WHERE id = #{env.id}")
    assert_not_includes raw.to_s, "super-secret-token"
    assert_equal "super-secret-token", env.reload.kube_token
  end

  test "kube_client builds a KubeClient from the environment's kube fields" do
    env = Environment.new(kube_api_url: "https://127.0.0.1:6443", kube_token_ciphertext: "tok", kube_ca_cert: "PEM")
    assert_instance_of KubeClient, env.kube_client
  end

  test "activate! sets this env active and deactivates others" do
    local = environments(:local_env)
    remote = environments(:tcp_env)
    assert local.active?
    remote.activate!
    assert remote.reload.active?
    assert_not local.reload.active?
  end

  test "activate! on the already-active environment leaves it active (not none)" do
    local = environments(:local_env)
    assert local.active?
    local.activate!
    assert local.reload.active?
    assert_equal local, Environment.active_env
  end

  test "active_env scope returns first active environment" do
    assert_equal environments(:local_env), Environment.active_env
  end
end

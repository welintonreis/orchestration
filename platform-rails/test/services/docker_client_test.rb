require "test_helper"

class DockerClientTest < ActiveSupport::TestCase
  def setup
    Rails.cache.clear
    Excon.defaults[:mock] = true
  end

  def teardown
    Excon.stubs.clear
    Excon.defaults[:mock] = false
  end

  test "runtime is docker when /version has no Podman component" do
    stub_path(/\/version$/, body: { "Components" => [{ "Name" => "Engine" }] }.to_json)
    client = DockerClient.new(endpoint: "unix:///tmp/docker-runtime-test.sock")
    assert_equal "docker", client.runtime
  end

  test "runtime is podman when /version reports Podman Engine component" do
    stub_path(/\/version$/, body: { "Components" => [{ "Name" => "Podman Engine" }] }.to_json)
    client = DockerClient.new(endpoint: "unix:///tmp/podman-runtime-test.sock")
    assert_equal "podman", client.runtime
  end

  test "runtime defaults to docker when the daemon is unreachable" do
    stub_path(/\/version$/, status: 500, body: "boom")
    client = DockerClient.new(endpoint: "unix:///tmp/unreachable-runtime-test.sock")
    assert_equal "docker", client.runtime
  end

  test "capabilities reports swarm true only for active docker swarm" do
    stub_path(/\/version$/, body: { "Components" => [{ "Name" => "Engine" }] }.to_json)
    stub_path(/\/info$/, body: { "Swarm" => { "LocalNodeState" => "active" } }.to_json)
    client = DockerClient.new(endpoint: "unix:///tmp/docker-swarm-active-test.sock")
    assert_equal({ swarm: true, compose: true, pods: false }, client.capabilities)
  end

  test "capabilities reports swarm false for podman regardless of LocalNodeState" do
    stub_path(/\/version$/, body: { "Components" => [{ "Name" => "Podman Engine" }] }.to_json)
    stub_path(/\/info$/, body: { "Swarm" => { "LocalNodeState" => "active" } }.to_json)
    client = DockerClient.new(endpoint: "unix:///tmp/podman-swarm-test.sock")
    assert_equal({ swarm: false, compose: true, pods: true }, client.capabilities)
  end

  test "capabilities reports swarm false for docker with inactive swarm" do
    stub_path(/\/version$/, body: { "Components" => [{ "Name" => "Engine" }] }.to_json)
    stub_path(/\/info$/, body: { "Swarm" => { "LocalNodeState" => "inactive" } }.to_json)
    client = DockerClient.new(endpoint: "unix:///tmp/docker-swarm-inactive-test.sock")
    assert_equal({ swarm: false, compose: true, pods: false }, client.capabilities)
  end

  test "capabilities fails safe (no swarm) when the daemon is unreachable" do
    stub_path(/\/version$/, status: 500, body: "boom")
    stub_path(/\/info$/, status: 500, body: "boom")
    client = DockerClient.new(endpoint: "unix:///tmp/unreachable-capabilities-test.sock")
    assert_equal({ swarm: false, compose: true, pods: false }, client.capabilities)
  end

  private

  def stub_path(path_regex, status: 200, body:)
    Excon.stub({ path: path_regex }, { status: status, body: body })
  end
end

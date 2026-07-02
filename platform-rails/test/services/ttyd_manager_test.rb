require "test_helper"

class TtydManagerTest < ActiveSupport::TestCase
  def manager
    TtydManager.instance
  end

  # dtach_socket

  test "dtach_socket returns stable path for same inputs" do
    sock1 = manager.send(:dtach_socket, "abc123def456xyz", "unix:///var/run/docker.sock", "root")
    sock2 = manager.send(:dtach_socket, "abc123def456xyz", "unix:///var/run/docker.sock", "root")
    assert_equal sock1, sock2
  end

  test "dtach_socket differs for different users" do
    sock_root = manager.send(:dtach_socket, "abc123def456", "unix:///var/run/docker.sock", "root")
    sock_app  = manager.send(:dtach_socket, "abc123def456", "unix:///var/run/docker.sock", "app")
    assert_not_equal sock_root, sock_app
  end

  test "dtach_socket differs for different endpoints" do
    sock_local  = manager.send(:dtach_socket, "abc123def456", "unix:///var/run/docker.sock", "root")
    sock_remote = manager.send(:dtach_socket, "abc123def456", "tcp://10.0.0.1:2376", "root")
    assert_not_equal sock_local, sock_remote
  end

  test "dtach_socket uses first 12 chars of container_id" do
    sock = manager.send(:dtach_socket, "abc123def456xyz789", nil, nil)
    assert_includes sock, "abc123def456"
    assert_not_includes sock, "xyz789"
  end

  test "dtach_socket path starts with /tmp/dtach-" do
    sock = manager.send(:dtach_socket, "abc123def456", nil, nil)
    assert sock.start_with?("/tmp/dtach-")
    assert sock.end_with?(".sock")
  end

  # dtach_enabled?

  test "dtach_enabled? false when DTACH_SESSIONS not set" do
    original = ENV["DTACH_SESSIONS"]
    ENV.delete("DTACH_SESSIONS")
    refute manager.send(:dtach_enabled?)
  ensure
    ENV["DTACH_SESSIONS"] = original
  end

  test "dtach_enabled? true when DTACH_SESSIONS=1" do
    original = ENV["DTACH_SESSIONS"]
    ENV["DTACH_SESSIONS"] = "1"
    assert manager.send(:dtach_enabled?)
  ensure
    ENV["DTACH_SESSIONS"] = original
  end

  test "dtach_enabled? false when DTACH_SESSIONS=0" do
    original = ENV["DTACH_SESSIONS"]
    ENV["DTACH_SESSIONS"] = "0"
    refute manager.send(:dtach_enabled?)
  ensure
    ENV["DTACH_SESSIONS"] = original
  end

  # docker_host

  test "docker_host returns nil for default unix socket" do
    assert_nil manager.send(:docker_host, "unix:///var/run/docker.sock")
  end

  test "docker_host returns nil for blank endpoint" do
    assert_nil manager.send(:docker_host, "")
    assert_nil manager.send(:docker_host, nil)
  end

  test "docker_host returns tcp endpoint as-is" do
    assert_equal "tcp://10.0.0.1:2376", manager.send(:docker_host, "tcp://10.0.0.1:2376")
  end

  # docker_exec_cmd

  test "docker_exec_cmd without dtach returns docker exec command" do
    original = ENV["DTACH_SESSIONS"]
    ENV.delete("DTACH_SESSIONS")
    cmd = manager.send(:docker_exec_cmd, "abc123", nil, nil)
    assert_equal "docker", cmd.first
    assert_includes cmd, "exec"
  ensure
    ENV["DTACH_SESSIONS"] = original
  end

  test "docker_exec_cmd with dtach prepends dtach" do
    original = ENV["DTACH_SESSIONS"]
    ENV["DTACH_SESSIONS"] = "1"
    cmd = manager.send(:docker_exec_cmd, "abc123def456", nil, "root")
    assert_equal "dtach", cmd.first
    assert_equal "-A", cmd[1]
  ensure
    ENV["DTACH_SESSIONS"] = original
  end

  test "docker_exec_cmd includes -u flag when user given" do
    original = ENV["DTACH_SESSIONS"]
    ENV.delete("DTACH_SESSIONS")
    cmd = manager.send(:docker_exec_cmd, "abc123", nil, "appuser")
    assert_includes cmd, "-u"
    idx = cmd.index("-u")
    assert_equal "appuser", cmd[idx + 1]
  ensure
    ENV["DTACH_SESSIONS"] = original
  end

  # kubectl_exec_cmd

  test "kubectl_exec_cmd sets KUBECONFIG via env, not kubectl argv" do
    cmd = manager.send(:kubectl_exec_cmd, "web-1", "default", nil, "/tmp/kubeconfig-abc")
    assert_equal "env", cmd.first
    assert_equal "KUBECONFIG=/tmp/kubeconfig-abc", cmd[1]
    assert_equal "kubectl", cmd[2]
    assert_not_includes cmd.join(" "), "--token"
  end

  test "kubectl_exec_cmd targets the given namespace and pod" do
    cmd = manager.send(:kubectl_exec_cmd, "web-1", "prod", nil, "/tmp/kc")
    assert_includes cmd, "-n"
    assert_equal "prod", cmd[cmd.index("-n") + 1]
    assert_includes cmd, "web-1"
  end

  test "kubectl_exec_cmd includes -c when a container is given" do
    cmd = manager.send(:kubectl_exec_cmd, "web-1", "default", "app", "/tmp/kc")
    assert_includes cmd, "-c"
    assert_equal "app", cmd[cmd.index("-c") + 1]
  end

  test "kubectl_exec_cmd omits the container flag when no container given" do
    # "-c" still appears once, from the trailing `/bin/sh -c "..."` — only
    # kubectl's own container flag (a second "-c" before the pod name) should
    # be absent.
    cmd = manager.send(:kubectl_exec_cmd, "web-1", "default", nil, "/tmp/kc")
    assert_equal 1, cmd.count("-c")
  end

  test "kubectl_exec_cmd probes for bash before falling back to sh" do
    cmd = manager.send(:kubectl_exec_cmd, "web-1", "default", nil, "/tmp/kc")
    assert_includes cmd.last, "command -v bash"
  end
end

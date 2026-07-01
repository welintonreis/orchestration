require "test_helper"
require "tmpdir"
require "fileutils"

class SecurityAuditTest < ActiveSupport::TestCase
  # ports (hex): 11434=2CAA, 443=01BB, 6380=18EC, 9999=270F, 22=0016
  def fake_proc(tcp:, tcp6: "sl local rem st\n")
    dir = Dir.mktmpdir
    FileUtils.mkdir_p("#{dir}/1/net")
    File.write("#{dir}/1/net/tcp", tcp)
    File.write("#{dir}/1/net/tcp6", tcp6)
    dir
  end

  def audit(tcp:, **rest)
    SecurityAudit.new(proc_path: fake_proc(tcp:, **rest))
  end

  test "flags sensitive service exposed publicly as critical" do
    a = audit(tcp: "sl local rem st\n0: 00000000:2CAA 00000000:0000 0A\n")
    f = a.findings.first
    assert_equal 11434, f.port
    assert_equal :critical, f.severity
  end

  test "expected public ports are ok" do
    a = audit(tcp: "sl local rem st\n0: 00000000:01BB 00000000:0000 0A\n")
    assert_equal :ok, a.findings.first.severity
  end

  test "unknown public port is a warning" do
    a = audit(tcp: "sl local rem st\n0: 00000000:270F 00000000:0000 0A\n")
    assert_equal :warning, a.findings.first.severity
  end

  test "loopback listeners are ignored" do
    # 0100007F = 127.0.0.1
    a = audit(tcp: "sl local rem st\n0: 0100007F:18EC 00000000:0000 0A\n")
    assert_empty a.findings
  end

  test "non-LISTEN sockets are ignored" do
    a = audit(tcp: "sl local rem st\n0: 00000000:2CAA 00000000:0000 01\n")
    assert_empty a.findings
  end

  test "score drops 20 per exposed sensitive service" do
    a = audit(tcp: "sl local rem st\n0: 00000000:2CAA 00000000:0000 0A\n1: 00000000:18EC 00000000:0000 0A\n")
    assert_equal 60, a.score
    assert_equal 2, a.summary[:critical]
  end

  test "missing proc path yields no findings, not a crash" do
    a = SecurityAudit.new(proc_path: "/nonexistent/proc")
    assert_empty a.findings
    assert_equal 100, a.score
  end

  test "host_state is nil when the collector file is missing" do
    a = SecurityAudit.new(proc_path: fake_proc(tcp: "sl local rem st\n"), security_path: "/nonexistent/state.json")
    assert_nil a.host_state
  end

  test "host_state parses the collector JSON, symbolized" do
    dir = fake_proc(tcp: "sl local rem st\n")
    path = "#{dir}/state.json"
    File.write(path, '{"fail2ban":{"running":true,"jails":[{"name":"sshd","currently_banned":2}]}}')
    a = SecurityAudit.new(proc_path: dir, security_path: path)
    assert_equal true, a.host_state[:fail2ban][:running]
    assert_equal 2, a.host_state[:fail2ban][:jails].first[:currently_banned]
  end

  test "host_state is memoized (file read once)" do
    dir = fake_proc(tcp: "sl local rem st\n")
    path = "#{dir}/state.json"
    File.write(path, '{"a":1}')
    a = SecurityAudit.new(proc_path: dir, security_path: path)
    a.host_state
    File.delete(path)
    assert_equal 1, a.host_state[:a]
  end

  test "container_diff is nil when the collector file is missing" do
    a = SecurityAudit.new(proc_path: fake_proc(tcp: "sl local rem st\n"), container_diff_path: "/nonexistent/container-diff.json")
    assert_nil a.container_diff
  end

  test "container_diff parses the collector JSON, symbolized" do
    dir = fake_proc(tcp: "sl local rem st\n")
    path = "#{dir}/container-diff.json"
    File.write(path, '{"containers":[{"name":"metabase","critical":[{"type":"C","path":"/etc/passwd"}]}]}')
    a = SecurityAudit.new(proc_path: dir, container_diff_path: path)
    assert_equal "metabase", a.container_diff[:containers].first[:name]
    assert_equal "/etc/passwd", a.container_diff[:containers].first[:critical].first[:path]
  end
end

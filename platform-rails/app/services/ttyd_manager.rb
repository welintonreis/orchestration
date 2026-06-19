require "socket"
require "singleton"

# Spawns and tracks one ttyd process per terminal session. ttyd serves an
# interactive PTY (docker exec) over a loopback WebSocket; ContainersController#
# ttyd_ws proxies the browser WS straight to it. Replaces the ActionCable +
# Solid Cable transport whose SQLite polling added ~100ms keystroke lag.
#
# Each session runs with `--once` so ttyd exits as soon as its single client
# (our proxy) disconnects — page navigation closes the browser WS, the proxy
# closes, ttyd dies, the port frees. get_or_spawn re-spawns if a tracked
# process already died.
class TtydManager
  include Singleton

  PORT_RANGE = (7681..7730).freeze
  BIND_ADDR  = "127.0.0.1"
  TTYD_BIN   = ENV.fetch("TTYD_BIN", "ttyd")
  START_WAIT = 3.0 # seconds to wait for ttyd to bind its port

  Session = Struct.new(:port, :pid)

  def initialize
    @mutex    = Mutex.new
    @sessions = {} # key => Session
  end

  # Loopback port serving a ttyd PTY for this session, spawning a fresh ttyd
  # if none is alive. The key isolates root vs non-root and different daemon
  # endpoints so they never share a process.
  def get_or_spawn(container_id, endpoint: nil, user: nil)
    key = session_key(container_id, endpoint, user)
    @mutex.synchronize do
      sess = @sessions[key]
      return sess.port if sess && alive?(sess.pid)

      cleanup_locked(key)
      sess = spawn_ttyd(container_id, endpoint, user)
      @sessions[key] = sess
      sess.port
    end
  end

  def cleanup(container_id, endpoint: nil, user: nil)
    @mutex.synchronize { cleanup_locked(session_key(container_id, endpoint, user)) }
  end

  private

  def session_key(container_id, endpoint, user)
    [container_id, endpoint, user].join("|")
  end

  def spawn_ttyd(container_id, endpoint, user)
    port = free_port
    cmd  = [TTYD_BIN, "--interface", BIND_ADDR, "--port", port.to_s,
            "--once", "--writable", "--"] + docker_exec_cmd(container_id, endpoint, user)
    # pgroup: true so the OS reaps the ttyd + its docker child if this process
    # dies; in/out/err to /dev/null since the proxy only talks to it over TCP.
    pid = Process.spawn(*cmd, in: "/dev/null", out: "/dev/null", err: "/dev/null", pgroup: true)
    Process.detach(pid)
    wait_for_port(port)
    Session.new(port, pid)
  end

  def docker_exec_cmd(container_id, endpoint, user)
    cmd  = ["docker"]
    host = docker_host(endpoint)
    cmd += ["-H", host] if host
    cmd += ["exec", "-it"]
    cmd += ["-u", user] if user.present?
    # Prefer bash, fall back to sh — same shell selection the old exec used.
    cmd + [container_id, "/bin/sh", "-c", "exec bash 2>/dev/null || exec sh"]
  end

  # The app's endpoint string (unix:///… or tcp://…) maps onto docker's -H flag;
  # the default local socket needs no -H.
  def docker_host(endpoint)
    return nil if endpoint.blank? || endpoint == "unix:///var/run/docker.sock"
    endpoint
  end

  def free_port
    used = @sessions.values.map(&:port)
    PORT_RANGE.find { |p| !used.include?(p) && port_free?(p) } ||
      raise("No free ttyd port in #{PORT_RANGE} (max #{PORT_RANGE.size} sessions)")
  end

  def port_free?(port)
    TCPServer.new(BIND_ADDR, port).close
    true
  rescue Errno::EADDRINUSE
    false
  end

  def wait_for_port(port)
    deadline = monotonic + START_WAIT
    loop do
      begin
        TCPSocket.new(BIND_ADDR, port).close
        return
      rescue Errno::ECONNREFUSED
        raise "ttyd failed to start on port #{port}" if monotonic > deadline
        sleep 0.05
      end
    end
  end

  def alive?(pid)
    return false unless pid
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH, Errno::EPERM
    false
  end

  def cleanup_locked(key)
    sess = @sessions.delete(key)
    return unless sess
    Process.kill("TERM", sess.pid)
  rescue Errno::ESRCH
    # already gone (--once exit) — nothing to kill
  end

  def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
end

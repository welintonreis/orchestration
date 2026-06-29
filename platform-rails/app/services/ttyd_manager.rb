require "socket"
require "securerandom"
require "singleton"
require "digest"

# Spawns and tracks one ttyd process per terminal connection. ttyd serves an
# interactive PTY (docker exec) over a loopback WebSocket; ContainersController#
# ttyd_ws proxies the browser WS straight to it. Replaces the ActionCable +
# Solid Cable transport whose SQLite polling added ~100ms keystroke lag.
#
# Each session runs with `--once`, so ttyd exits as soon as its single client
# (our proxy) disconnects. Because a `--once` process can only ever serve ONE
# connection, sessions are **never reused** — every ttyd_ws connection spawns a
# dedicated ttyd, tracked by a unique token. (The previous version reused a
# cached process keyed by container/user; every other connection then landed on
# an already-spent `--once` ttyd that refused the proxy's connection, so the WS
# upgrade hung and the terminal silently accepted no input.)
#
# Session persistence (DTACH_SESSIONS=1): wraps docker exec in dtach so the
# shell survives browser disconnects. dtach -A creates the session on first
# connect and reattaches on subsequent ones — the shell state (history, running
# commands) is preserved across reconnects to the same container+user+endpoint.
class TtydManager
  include Singleton

  PORT_RANGE = (7681..7730).freeze
  BIND_ADDR  = "127.0.0.1"
  TTYD_BIN   = ENV.fetch("TTYD_BIN", "ttyd")
  START_WAIT = 3.0 # seconds to wait for ttyd to bind its port

  Session = Struct.new(:token, :port, :pid)

  def initialize
    @mutex    = Mutex.new
    @sessions = {} # token => Session
  end

  # Spawn a fresh ttyd for one terminal connection; returns its Session
  # (token + loopback port). The caller proxies to BIND_ADDR:port and must call
  # stop(token) when the connection ends.
  def start(container_id, endpoint: nil, user: nil)
    @mutex.synchronize do
      token = SecureRandom.hex(8)
      @sessions[token] = spawn_ttyd(token, container_id, endpoint, user)
    end
  end

  # Tear down a session's ttyd. Idempotent: `--once` may have already exited it.
  def stop(token)
    return if token.nil?
    sess = @mutex.synchronize { @sessions.delete(token) }
    return unless sess
    Process.kill("TERM", sess.pid)
  rescue Errno::ESRCH
    # already gone (--once exit) — nothing to kill
  end

  private

  def spawn_ttyd(token, container_id, endpoint, user)
    port = free_port
    cmd  = [TTYD_BIN, "--interface", BIND_ADDR, "--port", port.to_s,
            "--once", "--writable", "--"] + docker_exec_cmd(container_id, endpoint, user)
    # pgroup: true so the OS reaps the ttyd + its docker child if this process
    # dies; in/out/err to /dev/null since the proxy only talks to it over TCP.
    pid = Process.spawn(*cmd, in: "/dev/null", out: "/dev/null", err: "/dev/null", pgroup: true)
    Process.detach(pid)
    wait_for_port(port)
    Session.new(token, port, pid)
  end

  def docker_exec_cmd(container_id, endpoint, user)
    cmd  = ["docker"]
    host = docker_host(endpoint)
    cmd += ["-H", host] if host
    cmd += ["exec", "-it"]
    cmd += ["-u", user] if user.present?
    # Prefer bash, fall back to sh.
    shell = [container_id, "/bin/sh", "-c", "exec bash 2>/dev/null || exec sh"]

    if dtach_enabled?
      # dtach -A: attach to existing session or create new one.
      # The shell persists after the browser disconnects — reconnecting to the
      # same container+user+endpoint lands back in the same running shell.
      ["dtach", "-A", dtach_socket(container_id, endpoint, user), "--"] + cmd + shell
    else
      cmd + shell
    end
  end

  def dtach_enabled?
    ENV["DTACH_SESSIONS"] == "1"
  end

  # Stable socket path per container+endpoint+user tuple so reconnects land
  # in the same dtach session. Short hash suffix keeps filename safe.
  def dtach_socket(container_id, endpoint, user)
    key = Digest::MD5.hexdigest("#{endpoint}:#{user}")[0..7]
    "/tmp/dtach-#{container_id[0..11]}-#{key}.sock"
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

  # Wait until ttyd is accepting connections. A bare TCP connect+close before any
  # WebSocket handshake does not count as ttyd's `--once` client, so this probe
  # does not consume the single allowed session.
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

  def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
end

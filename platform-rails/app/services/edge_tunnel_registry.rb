require "socket"
require "singleton"
require "securerandom"
require "timeout"
require "websocket/driver"

# Bridges Rails-side callers that expect a plain tcp://127.0.0.1:PORT Docker
# endpoint (DockerClient, TtydManager — nothing about them changes) to an
# edge node that only ever dials OUT to us.
#
# One persistent "control" WS per node (agent connects once, stays up) is
# used to ask the agent to open a fresh "data" WS whenever a local caller
# needs to reach the node's Docker socket. That's a deliberate departure
# from the spec's single-yamux-multiplexed-socket design: yamux has no
# mature Ruby implementation, and hand-rolling stream multiplexing with no
# live counterpart to test against is a bad place to introduce subtle bugs.
# N dedicated outbound connections (one per concurrent request) costs a bit
# more overhead per connection but is simple enough to reason about and to
# actually exercise end-to-end.
class EdgeTunnelRegistry
  include Singleton

  OPEN_STREAM_TIMEOUT = 10 # seconds to wait for the agent to dial back

  # Rack hijack sockets don't natively satisfy WebSocket::Driver's socket
  # interface (it just needs #env and #write) — this is that adapter.
  HijackSocket = Struct.new(:io, :env) do
    def write(data) = io.write(data)
  end

  def initialize
    @mutex    = Mutex.new
    @controls = {}   # node_id => WebSocket::Driver
    @waiting  = {}   # session_id => Queue (pairing handoff)
    @proxies  = {}   # node_id => { server:, port: }
  end

  # Called from the controller action after the WS handshake completes.
  # Blocks (in the request's own thread, same model as ContainersController
  # #ttyd_ws) parsing frames until the agent disconnects.
  def serve_control(node, io, driver)
    @mutex.synchronize { @controls[node.id] = driver }
    pump_incoming(io, driver)
  ensure
    @mutex.synchronize { @controls.delete(node.id) if @controls[node.id] == driver }
  end

  def serve_data_stream(session_id, io, driver)
    pairing = @mutex.synchronize { @waiting.delete(session_id) }
    return unless pairing # nobody's waiting (timed out, or unknown/replayed id) — just drop it

    out_queue = Queue.new
    driver.on(:message) { |e| out_queue.push(e.data) }
    driver.on(:close)   { out_queue.push(nil) }
    pairing.push([driver, out_queue])

    pump_incoming(io, driver)
  ensure
    out_queue&.push(nil)
  end

  # For Environment#effective_endpoint — returns a tcp:// endpoint whose
  # local proxy forwards to this node's Docker socket over the tunnel,
  # starting the local listener on first call.
  def proxy_endpoint_for(node)
    @mutex.synchronize do
      entry = @proxies[node.id]
      unless entry
        server = TCPServer.new("127.0.0.1", 0)
        entry = { server: server, port: server.addr[1] }
        @proxies[node.id] = entry
        Thread.new { accept_loop(node, server) }
      end
      "tcp://127.0.0.1:#{entry[:port]}"
    end
  end

  def online?(node) = @mutex.synchronize { @controls.key?(node.id) }

  private

  def accept_loop(node, server)
    loop do
      conn = server.accept
      Thread.new { bridge(node, conn) }
    end
  rescue IOError, Errno::EBADF
    nil # server closed
  end

  def bridge(node, local_conn)
    session_id = SecureRandom.hex(8)
    pairing = Queue.new
    @mutex.synchronize { @waiting[session_id] = pairing }

    unless request_open_stream(node, session_id)
      @mutex.synchronize { @waiting.delete(session_id) }
      return local_conn.close
    end

    driver, out_queue = wait_for_pairing(pairing)
    unless driver
      @mutex.synchronize { @waiting.delete(session_id) }
      return local_conn.close
    end

    upstream = Thread.new { pump_local_to_driver(local_conn, driver) }
    loop do
      chunk = out_queue.pop
      break if chunk.nil?
      local_conn.write(chunk)
    end
  rescue IOError, Errno::EBADF, Errno::ECONNRESET
    nil
  ensure
    upstream&.kill
    local_conn.close rescue nil
  end

  def wait_for_pairing(pairing)
    Timeout.timeout(OPEN_STREAM_TIMEOUT) { pairing.pop }
  rescue Timeout::Error
    nil
  end

  def pump_local_to_driver(local_conn, driver)
    loop { driver.binary(local_conn.readpartial(16_384)) }
  rescue EOFError, IOError, Errno::ECONNRESET
    nil
  ensure
    driver.close rescue nil
  end

  def request_open_stream(node, session_id)
    driver = @mutex.synchronize { @controls[node.id] }
    return false unless driver
    driver.text({ cmd: "open_stream", session_id: session_id }.to_json)
    true
  end

  # Shared by control and data connections: read raw bytes off the hijacked
  # socket and feed the driver, which dispatches :message/:close via the
  # callbacks each caller already wired up.
  def pump_incoming(io, driver)
    loop { driver.parse(io.readpartial(16_384)) }
  rescue EOFError, IOError, Errno::EBADF, Errno::ECONNRESET
    nil
  ensure
    driver.close rescue nil
    io.close rescue nil
  end
end

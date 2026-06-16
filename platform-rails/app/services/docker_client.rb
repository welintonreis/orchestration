class DockerClient
  class Error < StandardError; end
  class ConnectionError < Error; end
  class NotFoundError < Error; end

  HEADER_SIZE = 8

  def initialize(endpoint: "unix:///var/run/docker.sock")
    @endpoint = endpoint
    @connection = build_connection
  end

  # System

  def info
    get("/info")
  end

  def version
    get("/version")
  end

  # Containers

  def containers(all: false)
    get("/containers/json", query: { all: all ? 1 : 0 })
  end

  def container(id)
    get("/containers/#{id}/json")
  end

  def container_start(id)
    post("/containers/#{id}/start")
  end

  def container_stop(id, timeout: 10)
    post("/containers/#{id}/stop", query: { t: timeout })
  end

  def container_restart(id, timeout: 10)
    post("/containers/#{id}/restart", query: { t: timeout })
  end

  def container_kill(id, signal: "SIGKILL")
    post("/containers/#{id}/kill", query: { signal: signal })
  end

  def container_pause(id)
    post("/containers/#{id}/pause")
  end

  def container_unpause(id)
    post("/containers/#{id}/unpause")
  end

  def container_remove(id, force: false)
    delete("/containers/#{id}", query: { force: force ? 1 : 0 })
  end

  def container_logs(id, tail: 100, timestamps: false, &block)
    params = { stdout: 1, stderr: 1, follow: block_given? ? 1 : 0, tail: tail, timestamps: timestamps ? 1 : 0 }

    if block_given?
      stream("/containers/#{id}/logs", query: params, &block)
    else
      raw = raw_get("/containers/#{id}/logs", query: params)
      demux_stream(raw)
    end
  end

  def exec_create(container_id, cmd: ["sh", "-c", "exec bash 2>/dev/null || exec sh"], tty: true, user: nil, env: nil)
    body = { AttachStdin: true, AttachStdout: true, AttachStderr: true, Tty: tty, Cmd: cmd }
    body[:User] = user if user.present?
    body[:Env]  = Array(env).presence || ["TERM=xterm-256color"]
    post("/containers/#{container_id}/exec", body: body)
  end

  def exec_resize(exec_id, rows:, cols:)
    post("/exec/#{exec_id}/resize", query: { h: rows, w: cols })
  end

  def container_stats(id, &block)
    stream("/containers/#{id}/stats", query: { stream: 1 }) do |chunk|
      data = JSON.parse(chunk) rescue next
      block.call(data)
    end
  end

  # Images

  def images
    get("/images/json")
  end

  def image(id)
    get("/images/#{id}/json")
  end

  def image_remove(id, force: false)
    delete("/images/#{id}", query: { force: force ? 1 : 0 })
  end

  # Volumes

  def volumes
    get("/volumes")
  end

  def volume_remove(name, force: false)
    delete("/volumes/#{name}", query: { force: force ? 1 : 0 })
  end

  def system_df
    get("/system/df")
  end

  # Networks

  def networks
    get("/networks")
  end

  def network_remove(id)
    delete("/networks/#{id}")
  end

  # Swarm

  def swarm_info
    get("/swarm")
  end

  def services
    get("/services", query: { status: 1 })
  end

  def service(id)
    get("/services/#{id}")
  end

  def service_scale(id, replicas)
    svc     = service(id)
    version = svc.dig("Version", "Index")
    spec    = svc["Spec"].dup
    spec["Mode"] ||= {}
    spec["Mode"]["Replicated"] ||= {}
    spec["Mode"]["Replicated"]["Replicas"] = replicas
    post("/services/#{id}/update", query: { version: version }, body: spec)
  end

  def nodes
    get("/nodes")
  end

  # Configs (Swarm)

  def configs
    get("/configs")
  end

  def config_create(name:, data:, labels: {})
    post("/configs/create", body: {
      Name:   name,
      Labels: labels,
      Data:   Base64.strict_encode64(data)
    })
  end

  def config_remove(id)
    delete("/configs/#{id}")
  end

  # Secrets (Swarm)

  def secrets
    get("/secrets")
  end

  def secret_create(name:, data:, labels: {})
    post("/secrets/create", body: {
      Name:   name,
      Labels: labels,
      Data:   Base64.strict_encode64(data)
    })
  end

  def secret_remove(id)
    delete("/secrets/#{id}")
  end

  # Stacks (via docker stack ls — parses services label)

  def stacks
    svcs = services rescue []
    svcs
      .group_by { |s| s.dig("Spec", "Labels", "com.docker.stack.namespace") }
      .reject   { |ns, _| ns.nil? }
      .map do |ns, group|
        {
          "Name"       => ns,
          "Services"   => group.size,
          "Orchestrator" => "Swarm",
          "CreatedAt"  => group.map { |s| s["CreatedAt"] }.min
        }
      end
  end

  private

  def build_connection
    if @endpoint.start_with?("unix://")
      socket_path = @endpoint.sub("unix://", "")
      Excon.new("unix:///", socket: socket_path, persistent: true)
    elsif @endpoint.start_with?("tcp://")
      host = @endpoint.sub("tcp://", "http://")
      Excon.new(host, persistent: true)
    else
      raise ArgumentError, "Unsupported endpoint: #{@endpoint}"
    end
  rescue => e
    raise ConnectionError, "Cannot connect to Docker: #{e.message}"
  end

  def get(path, query: {})
    response = @connection.get(path: "/v1.47#{path}", query: query, headers: headers)
    parse_response(response)
  end

  def post(path, query: {}, body: nil)
    opts = { path: "/v1.47#{path}", query: query, headers: headers }
    opts[:body] = body.to_json if body
    response = @connection.post(**opts)
    parse_response(response)
  end

  def put(path, query: {}, body: nil)
    opts = { path: "/v1.47#{path}", query: query, headers: headers }
    opts[:body] = body.to_json if body
    response = @connection.put(**opts)
    parse_response(response)
  end

  def delete(path, query: {})
    response = @connection.delete(path: "/v1.47#{path}", query: query, headers: headers)
    parse_response(response)
  end

  def raw_get(path, query: {})
    response = @connection.get(path: "/v1.47#{path}", query: query, headers: headers)
    raise_for_status(response)
    response.body
  end

  def stream(path, query: {}, &block)
    @connection.get(
      path: "/v1.47#{path}",
      query: query,
      headers: headers,
      response_block: ->(chunk, _remaining, _total) { block.call(chunk) }
    )
  end

  def parse_response(response)
    raise_for_status(response)
    return nil if response.body.nil? || response.body.empty?
    JSON.parse(response.body)
  rescue JSON::ParserError
    response.body
  end

  def raise_for_status(response)
    case response.status
    when 200..299 then nil
    when 404 then raise NotFoundError, "Not found (#{response.status})"
    else raise Error, "Docker API error #{response.status}: #{response.body}"
    end
  end

  def headers
    { "Content-Type" => "application/json", "Accept" => "application/json" }
  end

  # Docker multiplexed stream format: 8-byte header per frame
  # [stream_type(1), 0, 0, 0, size(4 big-endian)] + payload
  def demux_stream(raw)
    output = +""
    pos = 0
    while pos + HEADER_SIZE <= raw.bytesize
      header = raw.byteslice(pos, HEADER_SIZE)
      size = header.byteslice(4, 4).unpack1("N")
      payload = raw.byteslice(pos + HEADER_SIZE, size).to_s
      output << payload
      pos += HEADER_SIZE + size
    end
    output
  end
end

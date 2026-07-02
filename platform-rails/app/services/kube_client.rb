require "tempfile"
require "tmpdir"
require "securerandom"
require "open3"
require "base64"
require "yaml"

# Kubernetes API client — Excon for reads/simple writes (same philosophy as
# DockerClient: no gem, a thin REST wrapper), kubectl CLI shellout for the
# two operations with hairy semantics (exec's SPDY/WebSocket multiplexing,
# apply's server-side merge). See docs/specs/feature-kubernetes-k3s.md.
class KubeClient
  class Error < StandardError; end
  class ConnectionError < Error; end
  class NotFoundError < Error; end
  class UnauthorizedError < Error; end

  WORKLOAD_PATHS = {
    "deployment"  => "deployments",
    "statefulset" => "statefulsets",
    "daemonset"   => "daemonsets"
  }.freeze

  def initialize(api_url:, token: nil, ca_cert: nil, client_cert: nil, client_key: nil)
    @api_url     = api_url.to_s.sub(%r{/\z}, "")
    @token       = token.presence
    @ca_cert     = ca_cert.presence
    @client_cert = client_cert.presence
    @client_key  = client_key.presence
    @connection  = build_connection
  end

  # Writes a throwaway kubeconfig (0600, never logged) so kubectl never sees
  # the token on argv (visible to every process in the container via /proc)
  # — same lesson as TtydManager's docker exec command. Auto-deletes when
  # the block returns; for short-lived shellouts (apply).
  def self.with_temp_kubeconfig(api_url:, token: nil, ca_cert: nil, client_cert: nil, client_key: nil)
    path = write_temp_kubeconfig(api_url: api_url, token: token, ca_cert: ca_cert, client_cert: client_cert, client_key: client_key)
    yield path
  ensure
    File.unlink(path) if path && File.exist?(path)
  end

  # Same content, but the caller owns cleanup — for a kubectl exec/ttyd
  # process that needs the kubeconfig to outlive this method call. Caller
  # must delete it (TtydManager does so in #stop). Deliberately NOT a
  # Tempfile here: Tempfile unlinks its file from a GC finalizer tied to the
  # object's lifetime, and returning only `.path` drops the last reference
  # to that object — the file could vanish out from under a still-running
  # kubectl process the moment GC runs. A plain path in system tmp avoids
  # that footgun entirely.
  def self.write_temp_kubeconfig(api_url:, token: nil, ca_cert: nil, client_cert: nil, client_key: nil)
    cluster = { "server" => api_url }
    cluster["certificate-authority-data"] = Base64.strict_encode64(ca_cert) if ca_cert.present?
    cluster["insecure-skip-tls-verify"] = true if ca_cert.blank?

    user = {}
    user["token"] = token if token.present?
    if client_cert.present? && client_key.present?
      user["client-certificate-data"] = Base64.strict_encode64(client_cert)
      user["client-key-data"] = Base64.strict_encode64(client_key)
    end

    config = {
      "apiVersion"      => "v1",
      "kind"            => "Config",
      "clusters"        => [{ "name" => "cluster", "cluster" => cluster }],
      "users"           => [{ "name" => "user", "user" => user }],
      "contexts"        => [{ "name" => "ctx", "context" => { "cluster" => "cluster", "user" => "user" } }],
      "current-context" => "ctx"
    }

    path = File.join(Dir.tmpdir, "kubeconfig-#{SecureRandom.hex(12)}")
    File.write(path, config.to_yaml)
    File.chmod(0o600, path)
    path
  end

  # System

  def namespaces
    get("/api/v1/namespaces")["items"]
  end

  def nodes
    get("/api/v1/nodes")["items"]
  end

  def version
    get_raw_path("/version")
  end

  # Cluster-wide (not namespace-scoped) — for the fleet view's summary
  # counts only; every other screen stays namespace-scoped per the spec's
  # own "namespace as primary filter" decision.
  def all_pods
    get("/api/v1/pods")["items"]
  end

  def all_deployments
    get("/apis/apps/v1/deployments")["items"]
  end

  # Metrics-server is optional — 404 means it's not installed, not an error.
  def top_pods(ns:)
    get("/apis/metrics.k8s.io/v1beta1/namespaces/#{ns}/pods")["items"]
  rescue NotFoundError
    []
  end

  # Pods

  def pods(ns:)
    get("/api/v1/namespaces/#{ns}/pods")["items"]
  end

  def pod(ns:, name:)
    get("/api/v1/namespaces/#{ns}/pods/#{name}")
  end

  def delete_pod(ns:, name:)
    delete("/api/v1/namespaces/#{ns}/pods/#{name}")
  end

  def pod_logs(ns:, name:, container: nil, tail: 200, &block)
    query = { tailLines: tail }
    query[:container] = container if container.present?

    if block_given?
      query[:follow] = true
      stream("/api/v1/namespaces/#{ns}/pods/#{name}/log", query: query, &block)
    else
      raw_get("/api/v1/namespaces/#{ns}/pods/#{name}/log", query: query)
    end
  end

  # Workloads (Deployments/StatefulSets/DaemonSets)

  def deployments(ns:)  = get("/apis/apps/v1/namespaces/#{ns}/deployments")["items"]
  def statefulsets(ns:) = get("/apis/apps/v1/namespaces/#{ns}/statefulsets")["items"]
  def daemonsets(ns:)   = get("/apis/apps/v1/namespaces/#{ns}/daemonsets")["items"]

  def scale(kind, name, ns:, replicas:)
    patch("/apis/apps/v1/namespaces/#{ns}/#{workload_path(kind)}/#{name}/scale",
          { spec: { replicas: replicas } })
  end

  def restart_workload(kind, name, ns:)
    body = { spec: { template: { metadata: { annotations: {
      "kubectl.kubernetes.io/restartedAt" => Time.current.iso8601
    } } } } }
    patch("/apis/apps/v1/namespaces/#{ns}/#{workload_path(kind)}/#{name}", body)
  end

  def delete_workload(kind, name, ns:)
    delete("/apis/apps/v1/namespaces/#{ns}/#{workload_path(kind)}/#{name}")
  end

  # Services

  def services(ns:) = get("/api/v1/namespaces/#{ns}/services")["items"]
  def delete_service(ns:, name:) = delete("/api/v1/namespaces/#{ns}/services/#{name}")

  # ConfigMaps / Secrets — read + delete only (parity with the Docker-side
  # Configs/Secrets screens, which are read+remove too — Kubernetes Secret
  # *values* aren't meant to round-trip through a web UI form any more than
  # a Swarm secret's are).

  def config_maps(ns:) = get("/api/v1/namespaces/#{ns}/configmaps")["items"]
  def delete_config_map(ns:, name:) = delete("/api/v1/namespaces/#{ns}/configmaps/#{name}")

  def secrets(ns:) = get("/api/v1/namespaces/#{ns}/secrets")["items"]
  def delete_secret(ns:, name:) = delete("/api/v1/namespaces/#{ns}/secrets/#{name}")

  # Apply — the k8s "deploy a stack" primitive. Shells out to kubectl
  # (server-side three-way merge) rather than reimplementing it.
  def apply(yaml_content)
    self.class.with_temp_kubeconfig(api_url: @api_url, token: @token, ca_cert: @ca_cert, client_cert: @client_cert, client_key: @client_key) do |kubeconfig|
      out, err, status = Open3.capture3(
        { "KUBECONFIG" => kubeconfig }, "kubectl", "apply", "-f", "-",
        stdin_data: yaml_content
      )
      { success: status.success?, output: [out, err].reject(&:blank?).join("\n") }
    end
  end

  private

  def workload_path(kind)
    WORKLOAD_PATHS[kind.to_s] || raise(ArgumentError, "unknown workload kind: #{kind}")
  end

  def build_connection
    opts = { persistent: false }
    if @ca_cert.present?
      @ca_cert_file = Tempfile.new("kube-ca")
      @ca_cert_file.write(@ca_cert)
      @ca_cert_file.close
      opts[:ssl_ca_file] = @ca_cert_file.path
    else
      opts[:ssl_verify_peer] = false
    end
    if @client_cert.present? && @client_key.present?
      opts[:client_cert_data] = @client_cert
      opts[:client_key_data]  = @client_key
    end
    Excon.new(@api_url, opts)
  rescue => e
    raise ConnectionError, "Cannot connect to Kubernetes API: #{e.message}"
  end

  def headers
    h = { "Accept" => "application/json" }
    h["Authorization"] = "Bearer #{@token}" if @token.present?
    h
  end

  def get(path, query: {})
    response = @connection.get(path: path, query: query, headers: headers)
    parse_response(response)
  end

  def get_raw_path(path)
    response = @connection.get(path: path, headers: headers)
    parse_response(response)
  end

  def patch(path, body)
    response = @connection.patch(
      path: path,
      headers: headers.merge("Content-Type" => "application/merge-patch+json"),
      body: body.to_json
    )
    parse_response(response)
  end

  def delete(path)
    response = @connection.delete(path: path, headers: headers)
    parse_response(response)
  end

  def raw_get(path, query: {})
    response = @connection.get(path: path, query: query, headers: headers)
    raise_for_status(response)
    response.body
  end

  def stream(path, query: {}, &block)
    @connection.get(
      path:           path,
      query:          query,
      headers:        headers,
      read_timeout:   nil,
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
    when 401, 403 then raise UnauthorizedError, "Kubernetes API unauthorized (#{response.status})"
    when 404 then raise NotFoundError, "Not found (#{response.status})"
    else raise Error, "Kubernetes API error #{response.status}: #{response.body}"
    end
  end
end

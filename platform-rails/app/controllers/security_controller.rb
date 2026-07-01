class SecurityController < ApplicationController
  before_action :require_admin!

  def index
    @audit          = SecurityAudit.new
    @findings       = @audit.findings
    @summary        = @audit.summary
    @score          = @audit.score
    @port_map       = docker_port_map
    @host_state     = @audit.host_state
    @container_diff = @audit.container_diff
  end

  private

  # port (Integer) => { stack:, service:, container_id:, container_name: }
  # Built from the LOCAL docker socket — /host/proc is always this host, so the
  # port map must come from this node's swarm, not the active environment.
  def docker_port_map
    client = DockerClient.new

    # swarm service name => first running container {id, name} on this node
    by_service = {}
    (client.containers(all: false) rescue []).each do |c|
      svc = c.dig("Labels", "com.docker.swarm.service.name")
      next unless svc
      by_service[svc] ||= {
        id:   c["Id"],
        name: c["Names"]&.first&.sub(%r{^/}, "") || c["Id"][0, 12]
      }
    end

    map = {}
    (client.services rescue []).each do |s|
      stack = s.dig("Spec", "Labels", "com.docker.stack.namespace")
      name  = s.dig("Spec", "Name")
      short = stack && name&.start_with?("#{stack}_") ? name.sub("#{stack}_", "") : name
      ctr   = by_service[name]
      Array(s.dig("Endpoint", "Ports")).each do |p|
        pub = p["PublishedPort"]
        next unless pub
        map[pub] = { stack:, service: short,
                     container_id: ctr&.dig(:id), container_name: ctr&.dig(:name) }
      end
    end
    map
  rescue StandardError
    {}
  end
end

class DashboardController < ApplicationController
  def index
    # Seven sequential Docker API round-trips made the dashboard take ~5.5s
    # on a busy host. Fan them out — one DockerClient per thread (an Excon
    # connection can't be shared across threads, same as
    # ContainersController#fetch_container_resources).
    endpoint = docker_endpoint
    fetch = {
      docker_info: -> (c) { c.info },
      containers:  -> (c) { c.containers(all: true) },
      images:      -> (c) { c.images },
      volumes:     -> (c) { c.volumes["Volumes"] || [] },
      networks:    -> (c) { c.networks },
      services:    -> (c) { c.services },
      nodes:       -> (c) { c.nodes }
    }
    results = fetch.map { |key, call|
      Thread.new { [key, (call.call(DockerClient.new(endpoint: endpoint)) rescue nil)] }
    }.map(&:value).to_h

    @docker_info = results[:docker_info] || {}
    @containers  = results[:containers]  || []
    @images      = results[:images]      || []
    @volumes     = results[:volumes]     || []
    @networks    = results[:networks]    || []

    @swarm_active = @docker_info["Swarm"]&.dig("LocalNodeState") == "active"
    @services     = @swarm_active ? (results[:services] || []) : []
    @nodes        = @swarm_active ? (results[:nodes]    || []) : []

    @latest_metric  = HostMetric.latest
    @metrics_24h    = HostMetric.last_24h.order(:created_at)
    @unread_alerts  = Alert.unread.recent.limit(5)
    @unread_count   = Alert.unread.count

    uptime_s       = File.read("/proc/uptime").split.first.to_f rescue 0
    @uptime_secs   = uptime_s.to_i
    @last_boot_at  = Time.now - @uptime_secs
  end
end

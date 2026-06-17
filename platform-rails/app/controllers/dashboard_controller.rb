class DashboardController < ApplicationController
  def index
    client = current_docker_client

    @docker_info = client.info rescue {}
    @containers  = client.containers(all: true) rescue []
    @images      = client.images rescue []
    @volumes     = (client.volumes rescue {})["Volumes"] || []
    @networks    = client.networks rescue []

    # Swarm
    @swarm_active = @docker_info["Swarm"]&.dig("LocalNodeState") == "active"
    if @swarm_active
      @services = client.services rescue []
      @nodes    = client.nodes rescue []
    else
      @services = []
      @nodes    = []
    end

    @latest_metric  = HostMetric.latest
    @metrics_24h    = HostMetric.last_24h.order(:created_at)
    @unread_alerts  = Alert.unread.recent.limit(5)
    @unread_count   = Alert.unread.count

    uptime_s       = File.read("/proc/uptime").split.first.to_f rescue 0
    @uptime_secs   = uptime_s.to_i
    @last_boot_at  = Time.now - @uptime_secs
  end
end

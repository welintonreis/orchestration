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
    @unread_alerts  = Alert.unread.recent.limit(5)
    @unread_count   = Alert.unread.count
  end
end

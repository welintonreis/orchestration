class NetworksController < ApplicationController
  PROTECTED_NETWORKS = %w[bridge host none].freeze

  def index
    @networks = current_docker_client.networks
  rescue => e
    @networks = []
    flash.now[:alert] = "Docker error: #{e.message}"
  end

  def show
    redirect_to networks_path
  end

  def remove
    network = current_docker_client.networks.find { |n| n["Id"] == params[:id] }
    if PROTECTED_NETWORKS.include?(network&.dig("Name"))
      redirect_to networks_path, alert: "Cannot remove built-in network."
      return
    end
    current_docker_client.network_remove(params[:id])
    redirect_to networks_path, notice: "Network removed."
  rescue => e
    redirect_to networks_path, alert: "Error: #{e.message}"
  end
end

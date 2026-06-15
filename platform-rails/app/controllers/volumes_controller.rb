class VolumesController < ApplicationController
  def index
    @volumes = current_docker_client.volumes["Volumes"] || []
  rescue => e
    @volumes = []
    flash.now[:alert] = "Docker error: #{e.message}"
  end

  def show
    # volumes don't have a detail endpoint in this client — redirect to index
    redirect_to volumes_path
  end

  def remove
    current_docker_client.volume_remove(params[:id], force: params[:force].present?)
    redirect_to volumes_path, notice: "Volume removed."
  rescue => e
    redirect_to volumes_path, alert: "Error: #{e.message}"
  end
end

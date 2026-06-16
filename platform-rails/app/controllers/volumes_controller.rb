class VolumesController < ApplicationController
  before_action :require_operator!, only: %i[remove batch_remove]

  def index
    @volumes = current_docker_client.volumes["Volumes"] || []
    df = current_docker_client.system_df rescue {}
    size_map = (df["Volumes"] || []).each_with_object({}) do |v, h|
      h[v["Name"]] = v.dig("UsageData", "Size").to_i
    end
    @volumes = @volumes.map { |v| v.merge("_size" => size_map[v["Name"]]) }
  rescue => e
    @volumes = []
    flash.now[:alert] = "Docker error: #{e.message}"
  end

  def show
    redirect_to volumes_path
  end

  def remove
    current_docker_client.volume_remove(params[:id], force: params[:force].present?)
    redirect_to volumes_path, notice: "Volume removido."
  rescue => e
    redirect_to volumes_path, alert: "Error: #{e.message}"
  end

  def batch_remove
    names  = Array(params[:names])
    errors = []
    names.each do |name|
      current_docker_client.volume_remove(name, force: true)
    rescue => e
      errors << e.message
    end
    removed = names.size - errors.size
    if errors.any?
      redirect_to volumes_path, alert: "#{removed} removido(s). Erros: #{errors.first(3).join('; ')}"
    else
      redirect_to volumes_path, notice: "#{removed} volume(s) removido(s)."
    end
  end
end

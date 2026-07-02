class ConfigsController < ApplicationController
  include SwarmGuard

  def index
    @configs = current_docker_client.configs
  rescue => e
    @configs = []
    flash.now[:alert] = "Erro Docker: #{e.message}"
  end

  def remove
    current_docker_client.config_remove(params[:id])
    redirect_to configs_path, notice: "Config removida."
  rescue => e
    redirect_to configs_path, alert: "Erro: #{e.message}"
  end
end

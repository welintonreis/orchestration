class SecretsController < ApplicationController
  before_action :require_operator!, only: %i[remove]

  def index
    @secrets = current_docker_client.secrets
  rescue => e
    @secrets = []
    flash.now[:alert] = "Erro Docker: #{e.message}"
  end

  def remove
    current_docker_client.secret_remove(params[:id])
    redirect_to secrets_path, notice: "Secret removida."
  rescue => e
    redirect_to secrets_path, alert: "Erro: #{e.message}"
  end
end

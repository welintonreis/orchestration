class SecretsController < ApplicationController
  before_action :require_operator!, only: %i[remove batch_remove]

  # remove/batch_remove redirect back here from inside the lazy
  # turbo-frame (secrets-content) — same self-referential nested-frame
  # bug fixed for ContainersController et al.
  def index
    rows if turbo_frame_request?
  end

  def rows
    @secrets = current_docker_client.secrets
    render "rows", layout: false
  rescue => e
    @secrets = []
    render "rows", layout: false
  end

  def remove
    current_docker_client.secret_remove(params[:id])
    redirect_to secrets_path, notice: "Secret removida."
  rescue => e
    redirect_to secrets_path, alert: "Erro: #{e.message}"
  end

  def batch_remove
    ids    = Array(params[:ids])
    errors = []
    ids.each { |id| current_docker_client.secret_remove(id) rescue errors << id }
    removed = ids.size - errors.size
    if errors.any?
      redirect_to secrets_path, alert: "#{removed} removida(s). Erros em: #{errors.first(3).join(', ')}"
    else
      redirect_to secrets_path, notice: "#{removed} secret(s) removida(s)."
    end
  end
end

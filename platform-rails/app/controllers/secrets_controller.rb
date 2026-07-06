class SecretsController < ApplicationController
  include SwarmGuard

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

  # remove/batch_remove are triggered by buttons living inside the
  # secrets-content turbo-frame, which redirect back to this same index —
  # a Turbo-Frame redirect to #index renders "rows" with layout: false (see
  # above), so shared/_flash (only rendered by the full layout) never
  # displays the notice/alert and Rails never sweeps it from the session:
  # the message silently survives into the next unrelated full-page
  # navigation. Render rows directly instead, using flash.now so this same
  # response shows it.
  def remove
    current_docker_client.secret_remove(params[:id])
    render_secrets_flash(notice: "Secret removida.")
  rescue => e
    render_secrets_flash(alert: "Erro: #{e.message}")
  end

  def batch_remove
    ids    = Array(params[:ids])
    errors = []
    ids.each { |id| current_docker_client.secret_remove(id) rescue errors << id }
    removed = ids.size - errors.size
    if errors.any?
      render_secrets_flash(alert: "#{removed} removida(s). Erros em: #{errors.first(3).join(', ')}")
    else
      render_secrets_flash(notice: "#{removed} secret(s) removida(s).")
    end
  end

  private

  def render_secrets_flash(notice: nil, alert: nil)
    if turbo_frame_request?
      flash.now[:notice] = notice if notice
      flash.now[:alert]  = alert  if alert
      rows
    else
      redirect_to secrets_path, notice: notice, alert: alert
    end
  end
end

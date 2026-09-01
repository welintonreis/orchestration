class VpsTerminalSessionsController < ApplicationController
  before_action :set_host, only: %i[index create]
  before_action :set_session, only: %i[terminal destroy reconnect]

  MAX_ACTIVE_SESSIONS = 5

  def index
    @sessions = @host.vps_terminal_sessions.recent.limit(10)
  end

  def create
    # Opening a host reuses its most recent session — the remote shell is still
    # alive under dtach/tmux, so you land back where you left off. `?new=1` (the
    # "+" in the tab bar) is the explicit opt-out: it forces a fresh session,
    # which the model assigns the lowest free slot and therefore its own shell.
    unless params[:new].present?
      existing = Current.user.vps_terminal_sessions.where(vps_host: @host).order(updated_at: :desc).first
      if existing && existing.status != "error"
        return redirect_to terminal_vps_host_terminal_session_path(@host, existing)
      end
    end

    active_count = Current.user.vps_terminal_sessions.active.count
    return redirect_to vps_hosts_path, alert: "Max #{MAX_ACTIVE_SESSIONS} sessões ativas." if active_count >= MAX_ACTIVE_SESSIONS

    session = Current.user.vps_terminal_sessions.create!(vps_host: @host, status: "connecting")
    AuditLog.record(user: Current.user, action: "vps_session.connected", target_type: "VpsTerminalSession",
                     target_id: session.id, metadata: { host: @host.hostname })
    redirect_to terminal_vps_host_terminal_session_path(@host, session)
  end

  def terminal
    @host = @session.vps_host
    @open_sessions = Current.user.vps_terminal_sessions.active.includes(:vps_host).order(:created_at).to_a
    @open_sessions << @session unless @open_sessions.any? { |s| s.id == @session.id }
  end

  def destroy
    # Kill the remote shell too: once the row is gone nothing knows this slot's
    # dtach socket / tmux name, so the shell would linger detached forever.
    service = VpsSshService.new(@session)
    service.disconnect
    service.kill_remote_shell
    VpsSftpPool.release(@session.vps_host_id)
    host = @session.vps_host
    session_id = @session.id
    @session.destroy
    AuditLog.record(user: Current.user, action: "vps_session.destroyed", target_type: "VpsTerminalSession", target_id: session_id)
    respond_to do |format|
      format.json { render json: { ok: true } }
      format.html { redirect_to vps_host_terminal_sessions_path(host), notice: "Sessão excluída com sucesso." }
    end
  end

  def reconnect
    @session.update!(status: "connecting", ended_at: nil, error_message: nil)
    respond_to do |format|
      format.json { render json: { ok: true } }
      format.html { redirect_to terminal_vps_host_terminal_session_path(@session.vps_host, @session) }
    end
  end

  private

  def set_host
    @host = VpsHost.find(params[:vps_host_id])
  end

  def set_session
    @session = Current.user.vps_terminal_sessions.find(params[:id])
  end
end

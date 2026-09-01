class VpsTerminalChannel < ApplicationCable::Channel
  def subscribed
    session = find_session
    return reject unless session

    # Host-key alerts and status messages are broadcast from the SSH thread
    # (which has no channel reference) — keep the stream for those.
    stream_from "vps_terminal_#{session.token}"
    @session_token = session.token
    @vps_session   = session
    @service       = VpsSshService.new(session)

    # PTY opens at the browser's real size instead of a stale/hardcoded
    # 80x24 — a remote PTY wider or narrower than the local renderer wraps
    # every long line at the wrong column.
    @service.connect(cols: params[:cols], rows: params[:rows]) do |data|
      # transmit goes straight to this connection's WebSocket — skips the
      # Solid Cable round-trip of broadcast (see SPEC-TERMINAL-TTYD.md).
      transmit({ output: Base64.strict_encode64(data) })
    end
  rescue => e
    Rails.logger.error("VpsTerminalChannel#subscribed error: #{e.message}")
    reject
  end

  def unsubscribed
    return unless @session_token
    @service&.disconnect
    AuditLog.record(
      user: current_user,
      action: "vps_session.disconnected",
      target_type: "VpsTerminalSession",
      target_id: @vps_session.id,
      metadata: { token: @session_token }
    )
  end

  # ActionCable routes messages with { action: "resize" } here directly
  def resize(data)
    @service&.resize(data["cols"].to_i, data["rows"].to_i)
  rescue => e
    Rails.logger.debug("VpsTerminalChannel#resize: #{e.message}")
  end

  def receive(data)
    return unless @service

    case data["action"]
    when "ping" then nil
    when "disconnect"
      @service.disconnect
      @vps_session.mark_disconnected!
      broadcast_status("disconnected")
    else
      @service.send_input(data["input"]) if data["input"]
    end
  rescue => e
    Rails.logger.warn("VpsTerminalChannel#receive error: #{e.class}: #{e.message}")
  end

  private

  def find_session
    token = params[:session_token]
    session = VpsTerminalSession.find_by(token: token)
    return nil unless session
    return nil unless session.user == current_user
    # A "disconnected" session is reconnectable, not dead: the shell lives on
    # under tmux/dtach and subscribing again just re-attaches.
    session.update_columns(status: "connecting", ended_at: nil, error_message: nil) if session.status != "connected"
    session
  end

  def broadcast_status(status, message: nil)
    ActionCable.server.broadcast(
      "vps_terminal_#{@session_token}",
      { status: status, message: message }.compact
    )
  end
end

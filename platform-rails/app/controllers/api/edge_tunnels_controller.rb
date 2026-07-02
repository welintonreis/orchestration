# Agent-facing WS endpoint — the agent is the one dialing US (never the
# other way around), for both the persistent control channel and every
# on-demand data stream. See EdgeTunnelRegistry for the pairing logic.
class Api::EdgeTunnelsController < ActionController::Base
  skip_forgery_protection

  def connect
    return head :bad_request unless request.env["HTTP_UPGRADE"].to_s.downcase == "websocket"

    node = authenticate_node
    return head :unauthorized unless node

    hijack = request.env["rack.hijack"]
    return head :internal_server_error unless hijack
    hijack.call
    io = request.env["rack.hijack_io"]

    socket = EdgeTunnelRegistry::HijackSocket.new(io, request.env)
    driver = WebSocket::Driver.rack(socket, protocols: [])
    unless driver.start
      io.close rescue nil
      return
    end

    if params[:role] == "data"
      EdgeTunnelRegistry.instance.serve_data_stream(params[:session_id].to_s, io, driver)
    else
      EdgeTunnelRegistry.instance.serve_control(node, io, driver)
    end
  ensure
    head :ok # ignored — socket was fully hijacked (same as ContainersController#ttyd_ws)
  end

  private

  def authenticate_node
    token, _options = ActionController::HttpAuthentication::Token.token_and_options(request)
    return nil if token.blank?
    EdgeNode.authenticate(token)
  end
end

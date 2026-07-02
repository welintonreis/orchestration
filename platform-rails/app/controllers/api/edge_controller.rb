# Agent-facing API — no session/cookie auth (the agent is a headless Go
# binary, not a browser). Enroll trades a short-lived enrollment token for
# a permanent per-node token; every other action authenticates with that
# token via a standard `Authorization: Bearer <token>` header.
class Api::EdgeController < ActionController::Base
  skip_forgery_protection

  before_action :authenticate_node!, except: :enroll

  def enroll
    data = EdgeEnrollmentToken.consume(params[:enrollment_token].to_s)
    return render json: { error: "invalid or expired enrollment token" }, status: :unauthorized unless data

    node, raw_token = EdgeNode.enroll!(name: data["name"], uuid: data["uuid"])
    node.touch_heartbeat!(agent_version: params[:agent_version], os: params[:os], arch: params[:arch])

    render json: { node_id: node.uuid, node_token: raw_token }, status: :created
  rescue ActiveRecord::RecordInvalid
    render json: { error: "enrollment token already used" }, status: :conflict
  end

  def heartbeat
    @current_node.touch_heartbeat!(agent_version: params[:agent_version], os: params[:os], arch: params[:arch])
    EdgeMetricsRecorder.record!(edge_node: @current_node, metrics: params[:metrics]) if params[:metrics].present?

    commands = @current_node.edge_commands.pending.map { |c| { id: c.id, kind: c.kind, payload: c.payload_data } }
    render json: { commands: commands }
  end

  def ack
    command = @current_node.edge_commands.find(params[:id])
    command.ack!(params[:result] || {})
    render json: { ok: true }
  rescue ActiveRecord::RecordNotFound
    render json: { error: "command not found" }, status: :not_found
  end

  private

  def authenticate_node!
    authenticate_or_request_with_http_token do |token, _options|
      @current_node = EdgeNode.authenticate(token)
    end
  end
end

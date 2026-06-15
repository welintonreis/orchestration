module SwarmGuard
  extend ActiveSupport::Concern

  included do
    before_action :require_swarm
  end

  private

  def require_swarm
    info = current_docker_client.info rescue {}
    unless info["Swarm"]&.dig("LocalNodeState") == "active"
      redirect_to root_path, alert: "Swarm is not active on this environment."
    end
  end
end

module SwarmGuard
  extend ActiveSupport::Concern

  included do
    before_action :require_swarm
  end

  private

  def require_swarm
    unless current_docker_client.capabilities[:swarm]
      redirect_to root_path, alert: "Swarm is not active on this environment."
    end
  end
end

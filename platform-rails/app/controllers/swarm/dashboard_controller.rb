module Swarm
  class DashboardController < ApplicationController
    include SwarmGuard

    def index
      @swarm   = current_docker_client.swarm_info
      @nodes   = current_docker_client.nodes
      @info    = current_docker_client.info
    rescue => e
      @swarm = @nodes = @info = nil
      flash.now[:alert] = "Swarm error: #{e.message}"
    end
  end
end

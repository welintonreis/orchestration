module Swarm
  class DashboardController < ApplicationController
    include SwarmGuard

    # Shell only. SwarmGuard still runs here, so an environment without a
    # swarm is redirected before any skeleton is painted; the three serial
    # socket calls live in #rows.
    def index
    end

    def rows
      @swarm   = current_docker_client.swarm_info
      @nodes   = current_docker_client.nodes
      @info    = current_docker_client.info
    rescue => e
      @swarm = @nodes = @info = nil
      flash.now[:alert] = "Swarm error: #{e.message}"
    end
  end
end

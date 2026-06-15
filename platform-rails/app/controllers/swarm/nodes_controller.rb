module Swarm
  class NodesController < ApplicationController
    include SwarmGuard

    def index
      @nodes = current_docker_client.nodes
    rescue => e
      @nodes = []
      flash.now[:alert] = "Swarm error: #{e.message}"
    end
  end
end

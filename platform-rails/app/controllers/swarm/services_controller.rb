module Swarm
  class ServicesController < ApplicationController
    include SwarmGuard

    def index
      @services = current_docker_client.services
      @nodes    = current_docker_client.nodes
    rescue => e
      @services = []
      @nodes    = []
      flash.now[:alert] = "Swarm error: #{e.message}"
    end
  end
end

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

    def scale
      replicas = params[:replicas].to_i
      current_docker_client.service_scale(params[:id], replicas)
      redirect_to swarm_services_path, notice: "Serviço escalado para #{replicas} réplica(s)"
    rescue => e
      redirect_to swarm_services_path, alert: "Erro ao escalar: #{e.message}"
    end

    def drain
      current_docker_client.service_scale(params[:id], 0)
      redirect_to swarm_services_path, notice: "Serviço desidratado (0 réplicas)"
    rescue => e
      redirect_to swarm_services_path, alert: "Erro ao desidratar: #{e.message}"
    end
  end
end

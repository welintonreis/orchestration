class StacksController < ApplicationController
  def index
    all_services = current_docker_client.services rescue []
    @stacks = all_services
      .group_by { |s| s.dig("Spec", "Labels", "com.docker.stack.namespace") }
      .reject    { |ns, _| ns.nil? }
      .map do |ns, svcs|
        {
          "Name"        => ns,
          "Services"    => svcs.size,
          "Orchestrator"=> "Swarm",
          "CreatedAt"   => svcs.map { |s| s["CreatedAt"] }.min,
          "ServiceList" => svcs
        }
      end
      .sort_by { |s| s["Name"] }
  rescue => e
    @stacks = []
    flash.now[:alert] = "Erro Docker: #{e.message}"
  end

  def scale_service
    replicas = params[:replicas].to_i
    current_docker_client.service_scale(params[:service_id], replicas)
    redirect_to stacks_path, notice: "Serviço escalado para #{replicas} réplica(s)"
  rescue => e
    redirect_to stacks_path, alert: "Erro ao escalar: #{e.message}"
  end

  def drain_stack_service
    current_docker_client.service_scale(params[:service_id], 0)
    redirect_to stacks_path, notice: "Serviço desidratado (0 réplicas)"
  rescue => e
    redirect_to stacks_path, alert: "Erro ao desidratar: #{e.message}"
  end
end

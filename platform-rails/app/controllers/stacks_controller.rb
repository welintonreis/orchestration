class StacksController < ApplicationController
  # scale_service/drain_stack_service redirect back here from inside the
  # lazy turbo-frame (stacks-content) — same self-referential nested-frame
  # bug fixed for ContainersController/Swarm::ServicesController: a
  # Turbo-Frame-header redirect rendering the skeleton+nested lazy-frame
  # shell never re-fires the follow-up fetch. Render rows directly instead.
  def index
    rows if turbo_frame_request?
  end

  def rows
    all_services = current_docker_client.services rescue []
    @nodes       = current_docker_client.nodes    rescue []
    @stacks = all_services
      .group_by { |s| s.dig("Spec", "Labels", "com.docker.stack.namespace") }
      .reject    { |ns, _| ns.nil? }
      .map do |ns, svcs|
        active = svcs.any? { |s| s.dig("ServiceStatus", "RunningTasks").to_i > 0 }
        {
          "Name"        => ns,
          "Services"    => svcs.size,
          "Orchestrator"=> "Swarm",
          "CreatedAt"   => svcs.map { |s| s["CreatedAt"] }.min,
          "ServiceList" => svcs,
          "Active"      => active
        }
      end
      .sort_by { |s| s["Name"] }
    render "rows", layout: false
  rescue => e
    @stacks = []
    @nodes  = []
    render "rows", layout: false
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

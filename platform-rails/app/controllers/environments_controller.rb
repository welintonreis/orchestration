class EnvironmentsController < ApplicationController
  before_action :set_environment, only: %i[destroy activate]

  def index
    @environments = Environment.order(:name)
    @stats = {}

    @environments.each do |env|
      begin
        client = DockerClient.new(endpoint: env.effective_endpoint)
        info   = client.info

        swarm_active = info.dig("Swarm", "LocalNodeState") == "active"
        containers   = client.containers(all: true) rescue []
        images       = client.images rescue []
        volumes_data = client.volumes rescue {}
        volumes      = volumes_data["Volumes"] || []
        networks     = client.networks rescue []
        services     = swarm_active ? (client.services rescue []) : []
        nodes        = swarm_active ? (client.nodes rescue []) : []

        running = containers.count { |c| c["State"] == "running" }
        healthy = containers.count { |c| c.dig("Status").to_s.include?("healthy") }
        unhealthy = containers.count { |c| c.dig("Status").to_s.include?("unhealthy") }

        # Stack running/stopped: a stack counts as running if any of its
        # services has at least one running task.
        services_by_stack = services.group_by { |s| s.dig("Spec", "Labels", "com.docker.stack.namespace") }.compact
        stacks_running = services_by_stack.count { |_, svcs| svcs.sum { |s| s.dig("ServiceStatus", "RunningTasks").to_i } > 0 }
        stacks_stopped = services_by_stack.size - stacks_running

        # Service complete/degraded: RunningTasks vs DesiredTasks, which
        # Docker computes from the daemon for both replicated and global
        # modes (status=1 query already requested in DockerClient#services).
        # A service scaled to 0 replicas (desired=0) is complete, not
        # degraded — it's exactly matching its (zero) desired state, just
        # intentionally off. Only desired > running counts as a shortfall.
        services_complete = services.count do |s|
          desired = s.dig("ServiceStatus", "DesiredTasks").to_i
          running_tasks = s.dig("ServiceStatus", "RunningTasks").to_i
          running_tasks >= desired
        end
        services_degraded = services.size - services_complete

        @stats[env.id] = {
          up:          true,
          swarm:       swarm_active,
          docker_ver:  info["ServerVersion"],
          ncpu:        info["NCPU"],
          mem_total:   info["MemTotal"],
          containers:  containers.size,
          running:     running,
          healthy:     healthy,
          unhealthy:   unhealthy,
          images:      images.size,
          volumes:     volumes.size,
          networks:    networks.size,
          services:    services.size,
          services_complete: services_complete,
          services_degraded: services_degraded,
          nodes:       nodes.size,
          stacks:      services_by_stack.size,
          stacks_running: stacks_running,
          stacks_stopped: stacks_stopped,
        }
      rescue => e
        @stats[env.id] = { up: false, error: e.message }
      end
    end
  end

  def new
    @environment = Environment.new
  end

  def create
    @environment = Environment.new(environment_params)
    if @environment.save
      begin
        DockerClient.new(endpoint: @environment.effective_endpoint).info
        flash[:notice] = "Ambiente \"#{@environment.name}\" criado e acessível."
      rescue => e
        flash[:notice] = "Ambiente \"#{@environment.name}\" criado, mas sem acesso ao Docker: #{e.message}"
      end
      redirect_to environments_path
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    if Environment.count == 1
      flash[:alert] = "Não é possível remover o único ambiente."
      redirect_to environments_path
      return
    end
    name = @environment.name
    @environment.destroy
    flash[:notice] = "Ambiente \"#{name}\" removido."
    redirect_to environments_path
  end

  def activate
    @environment.activate!
    cookies[:active_env] = { value: @environment.id.to_s, expires: 1.year.from_now }
    flash[:notice] = "Ambiente ativo: \"#{@environment.name}\"."
    redirect_to root_path
  end

  private

  def set_environment
    @environment = Environment.find(params[:id])
  end

  def environment_params
    params.require(:environment).permit(:name, :endpoint_type, :endpoint)
  end
end

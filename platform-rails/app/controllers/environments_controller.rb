class EnvironmentsController < ApplicationController
  before_action :require_admin!, except: %i[index activate]
  before_action :set_environment, only: %i[destroy activate]

  def index
    @environments = Environment.order(:name)
    @stats = {}

    @environments.each do |env|
      begin
        client = DockerClient.new(endpoint: env.endpoint)
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
          nodes:       nodes.size,
          stacks:      services.map { |s| s.dig("Spec", "Labels", "com.docker.stack.namespace") }.uniq.compact.size,
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
        DockerClient.new(endpoint: @environment.endpoint).info
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

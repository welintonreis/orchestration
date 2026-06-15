class ContainersController < ApplicationController
  def index
    @all = params[:filter] != "running"
    @containers = current_docker_client.containers(all: @all)
  rescue => e
    @containers = []
    flash.now[:alert] = "Docker error: #{e.message}"
  end

  def show
    @container = current_docker_client.container(params[:id])
  rescue DockerClient::NotFoundError
    redirect_to containers_path, alert: "Container not found."
  end

  def logs
    @container_id = params[:id]
    @tail = (params[:tail] || 200).to_i
    @logs = current_docker_client.container_logs(@container_id, tail: @tail)
  rescue => e
    @logs = "Error fetching logs: #{e.message}"
  end

  # Action methods — all POST/DELETE, redirect back
  %w[start stop restart kill pause unpause].each do |action|
    define_method(action) do
      current_docker_client.public_send("container_#{action}", params[:id])
      redirect_to containers_path, notice: "Container #{action}ed."
    rescue => e
      redirect_to containers_path, alert: "Error: #{e.message}"
    end
  end

  def remove
    current_docker_client.container_remove(params[:id], force: params[:force].present?)
    redirect_to containers_path, notice: "Container removed."
  rescue => e
    redirect_to containers_path, alert: "Error: #{e.message}"
  end
end

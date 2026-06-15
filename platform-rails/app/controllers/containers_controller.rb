class ContainersController < ApplicationController
  before_action :require_operator!, only: %i[start stop restart kill pause unpause remove]

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
      AuditLog.record(user: Current.user, action: "container_#{action}",
                      target_type: "Container", target_id: params[:id],
                      ip_address: request.remote_ip)
      redirect_to containers_path, notice: "Container #{action}ed."
    rescue => e
      redirect_to containers_path, alert: "Error: #{e.message}"
    end
  end

  def remove
    current_docker_client.container_remove(params[:id], force: params[:force].present?)
    AuditLog.record(user: Current.user, action: "container_remove",
                    target_type: "Container", target_id: params[:id],
                    ip_address: request.remote_ip)
    redirect_to containers_path, notice: "Container removed."
  rescue => e
    redirect_to containers_path, alert: "Error: #{e.message}"
  end
end

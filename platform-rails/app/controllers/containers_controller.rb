class ContainersController < ApplicationController
  before_action :require_operator!, only: %i[start stop restart kill pause unpause remove bulk_action]

  def index
    all_containers  = current_docker_client.containers(all: true)
    selected        = Array(params[:statuses]).map(&:downcase).reject(&:blank?)
    all_containers  = all_containers.select { |c| selected.include?(c["State"].to_s.downcase) } if selected.any?
    @selected_statuses = selected
    @total          = all_containers.size
    @per_page       = params[:per_page] == "0" ? nil : (params[:per_page]&.to_i || 10)
    @page           = [params[:page]&.to_i || 1, 1].max
    if @per_page
      @total_pages = [(@total.to_f / @per_page).ceil, 1].max
      @page        = [@page, @total_pages].min
      @containers  = all_containers.drop((@page - 1) * @per_page).first(@per_page)
    else
      @total_pages = 1
      @containers  = all_containers
    end
  rescue => e
    @containers = []
    @total = @page = @total_pages = 0
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

  def terminal
    @container_id   = params[:id]
    @container      = current_docker_client.container(@container_id)
    @container_name = @container.dig("Name")&.sub(/^\//, "") || @container_id[0..11]
    @endpoint       = active_environment&.endpoint || "unix:///var/run/docker.sock"
    @exec_user      = params[:root] == "1" ? "root" : params[:user].presence
  rescue DockerClient::NotFoundError
    redirect_to containers_path, alert: "Container not found."
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

  def bulk_action
    ids        = Array(params[:ids]).reject(&:blank?)
    action     = params[:action_type].to_s
    allowed    = %w[start stop restart kill pause unpause remove]

    return redirect_to containers_path, alert: "No containers selected."  if ids.empty?
    return redirect_to containers_path, alert: "Invalid action."          unless allowed.include?(action)

    errors = []
    ids.each do |id|
      begin
        if action == "remove"
          current_docker_client.container_remove(id, force: false)
        else
          current_docker_client.public_send("container_#{action}", id)
        end
        AuditLog.record(user: Current.user, action: "container_#{action}",
                        target_type: "Container", target_id: id,
                        ip_address: request.remote_ip)
      rescue => e
        errors << "#{id[0..11]}: #{e.message}"
      end
    end

    if errors.any?
      redirect_to containers_path, alert: "#{errors.size} error(s): #{errors.first(3).join('; ')}"
    else
      redirect_to containers_path, notice: "#{action.capitalize}ed #{ids.size} container(s)."
    end
  end
end

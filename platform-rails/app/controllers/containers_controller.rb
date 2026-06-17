class ContainersController < ApplicationController
  before_action :require_operator!, only: %i[start stop restart kill pause unpause remove bulk_action prune]

  def index
  end

  def rows
    all_containers  = current_docker_client.containers(all: true)
    selected        = Array(params[:statuses]).map(&:downcase).reject(&:blank?)
    all_containers  = all_containers.select { |c| selected.include?(c["State"].to_s.downcase) } if selected.any?
    @selected_statuses = selected

    @infra_filter = params[:infra].presence
    resources_cache = {}
    if @infra_filter.present? && @infra_filter != "all"
      resources_cache = fetch_container_resources(all_containers.map { |c| c["Id"] })
      all_containers  = all_containers.select { |c| infra_status_for(resources_cache[c["Id"]]) == @infra_filter }
    end

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

    missing_ids = @containers.map { |c| c["Id"] } - resources_cache.keys
    resources_cache.merge!(fetch_container_resources(missing_ids)) if missing_ids.any?
    @container_resources = resources_cache.slice(*@containers.map { |c| c["Id"] })
    render layout: false
  rescue => e
    @containers = []
    @container_resources = {}
    @total = @page = @total_pages = 0
    @selected_statuses = []
    @infra_filter = nil
    render layout: false
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

  def prune
    result = current_docker_client.containers_prune
    count  = (result["ContainersDeleted"] || []).size
    freed  = result.dig("SpaceReclaimed").to_i
    freed_mb = freed > 0 ? " (#{(freed.to_f / 1_048_576).round(1)} MB liberados)" : ""
    redirect_to containers_path, notice: "#{count} container(s) parado(s) removido(s).#{freed_mb}"
  rescue => e
    redirect_to containers_path, alert: "Erro ao limpar containers: #{e.message}"
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

  private

  CONCURRENCY = 12

  def fetch_container_resource(id)
    Rails.cache.fetch("container_resource/#{active_environment&.id}/#{id}", expires_in: 20.seconds) do
      detail    = current_docker_client.container(id)
      memory    = detail.dig("HostConfig", "Memory").to_i
      nano_cpus = detail.dig("HostConfig", "NanoCpus").to_i
      cpu_quota = detail.dig("HostConfig", "CpuQuota").to_i
      {
        memory:    memory > 0,
        cpu:       nano_cpus > 0 || cpu_quota > 0,
        mem_bytes: memory,
        nano_cpus: nano_cpus,
        cpu_quota: cpu_quota
      }
    end
  rescue
    nil
  end

  # Inspects many containers concurrently — sequential inspects (one HTTP
  # round-trip per container) is what made /containers freeze with the
  # "infra" filter or "Todos" page size on hosts with many containers.
  def fetch_container_resources(ids)
    results = Concurrent::Hash.new
    ids.each_slice(CONCURRENCY) do |batch|
      batch.map { |id| Thread.new { results[id] = fetch_container_resource(id) } }.each(&:join)
    end
    results
  end

  def infra_status_for(res)
    return "unknown" if res.nil?
    (res[:memory] && res[:cpu]) ? "limited" : "unlimited"
  end
end

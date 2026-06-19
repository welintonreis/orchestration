class ContainersController < ApplicationController
  before_action :require_operator!, only: %i[start stop restart kill pause unpause remove bulk_action prune]

  # Filter/per_page/pagination links inside rows.html.erb point back here
  # (not directly at rows_containers_path) so the URL bar reflects the
  # current filter state. When that request arrives as a turbo-frame
  # navigation (clicked from inside the already-loaded frame, not a
  # fresh page load), render the rows content directly instead of the
  # skeleton+lazy-frame shell — nesting a turbo-frame inside the very
  # frame being re-navigated is an unreliable pattern that silently
  # never re-fired the follow-up fetch.
  def index
    rows if turbo_frame_request?
  end

  SORTABLE_COLUMNS = %w[name status health infra].freeze

  def rows
    all_containers  = current_docker_client.containers(all: true)
    selected        = Array(params[:statuses]).map(&:downcase).reject(&:blank?)
    all_containers  = all_containers.select { |c| selected.include?(c["State"].to_s.downcase) } if selected.any?
    @selected_statuses = selected

    # Was client-side JS filtering only the rows already rendered on the
    # current page (e.g. 10 of N containers) — search needs to run against
    # every container before pagination, same as the other filters.
    @query = params[:q].to_s.strip
    if @query.present?
      q = @query.downcase
      all_containers = all_containers.select do |c|
        name  = (c["Names"]&.first&.sub(/^\//, "") || "").downcase
        image = c["Image"].to_s.downcase
        name.include?(q) || image.include?(q) || c["Id"].to_s.start_with?(q)
      end
    end

    @sort     = SORTABLE_COLUMNS.include?(params[:sort].to_s) ? params[:sort].to_s : nil
    @sort_dir = params[:dir] == "desc" ? "desc" : "asc"

    @infra_filter = params[:infra].presence
    resources_cache = {}
    # infra needs every container inspected up front to filter+sort
    # correctly (not just the current page) — same fan-out as the filter
    # already needed, just also triggered by sort=infra now.
    if (@infra_filter.present? && @infra_filter != "all") || @sort == "infra"
      resources_cache = fetch_container_resources(all_containers.map { |c| c["Id"] })
      all_containers  = all_containers.select { |c| infra_status_for(resources_cache[c["Id"]]) == @infra_filter } if @infra_filter.present? && @infra_filter != "all"
    end

    all_containers = sort_containers(all_containers, @sort, @sort_dir, resources_cache) if @sort

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
    render "rows", layout: false
  rescue => e
    @containers = []
    @container_resources = {}
    @total = @page = @total_pages = 0
    @selected_statuses = []
    @infra_filter = nil
    @query = ""
    @sort = nil
    @sort_dir = "asc"
    render "rows", layout: false
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

  # Raw WebSocket proxy: hijacks the Rack socket and pipes bytes straight to a
  # ttyd process (spawned per session by TtydManager) serving `docker exec`.
  # This replaces the ActionCable terminal transport — no Solid Cable / SQLite
  # in the path, so keystroke latency drops from ~100ms to <5ms. The browser's
  # WS upgrade handshake is replayed to ttyd verbatim (same Sec-WebSocket-Key),
  # so ttyd's computed accept matches and the proxy never parses WS frames.
  #
  # Blocks one Puma thread for the lifetime of the terminal (raise
  # WEB_CONCURRENCY if many concurrent sessions are expected).
  def ttyd_ws
    return head :bad_request unless request.env["HTTP_UPGRADE"].to_s.downcase == "websocket"

    endpoint = active_environment&.endpoint
    user     = params[:root] == "1" ? "root" : params[:user].presence
    session  = TtydManager.instance.start(params[:id], endpoint: endpoint, user: user)

    hijack = request.env["rack.hijack"]
    return head :internal_server_error unless hijack
    hijack.call
    browser = request.env["rack.hijack_io"]
    ttyd    = TCPSocket.new(TtydManager::BIND_ADDR, session.port)

    # Disable Nagle on both sides. Each keystroke is a tiny packet; with Nagle on,
    # TCP holds it waiting for an ACK of the previous small segment (which delayed
    # ACK sits on for ~40ms), so typing echo stalls ~40ms/char even though ttyd
    # itself is <5ms. nodelay sends each segment immediately.
    enable_nodelay(browser)
    enable_nodelay(ttyd)

    ttyd.write(ttyd_handshake(request.env))

    up   = Thread.new { IO.copy_stream(browser, ttyd) rescue nil; close_quietly(ttyd) }
    down = Thread.new { IO.copy_stream(ttyd, browser) rescue nil; close_quietly(browser) }
    up.join
    down.join
  ensure
    close_quietly(browser)
    close_quietly(ttyd)
    TtydManager.instance.stop(session&.token) rescue nil
    head :ok # ignored — the socket was fully hijacked
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
    AuditLog.record(user: Current.user, action: "containers_prune",
                    metadata: { count: count, space_reclaimed_bytes: freed,
                                deleted: result["ContainersDeleted"] || [] })
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

  # Replays the browser's WS upgrade onto ttyd's /ws endpoint. Forwarding the
  # same Sec-WebSocket-Key/Version/Protocol means ttyd's 101 response carries an
  # accept hash the browser already expects — no per-side handshake math needed.
  # ttyd requires the "tty" subprotocol.
  def ttyd_handshake(env)
    key      = env["HTTP_SEC_WEBSOCKET_KEY"]
    version  = env["HTTP_SEC_WEBSOCKET_VERSION"].presence || "13"
    protocol = env["HTTP_SEC_WEBSOCKET_PROTOCOL"].presence || "tty"
    [
      "GET /ws HTTP/1.1",
      "Host: #{TtydManager::BIND_ADDR}",
      "Upgrade: websocket",
      "Connection: Upgrade",
      "Sec-WebSocket-Key: #{key}",
      "Sec-WebSocket-Version: #{version}",
      "Sec-WebSocket-Protocol: #{protocol}",
      "", ""
    ].join("\r\n")
  end

  def enable_nodelay(io)
    io.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
  rescue StandardError
    nil # not a TCP socket (or already closed) — nothing to tune
  end

  def close_quietly(io)
    io&.close
  rescue IOError, Errno::EBADF
    nil
  end

  CONCURRENCY = 12

  def fetch_container_resource(id, client = current_docker_client)
    # Memory/CPU limits never change for a running container without
    # recreating it (which gets a new Id, naturally busting this key), so
    # a long TTL is safe and makes the infra filter fast on repeat use —
    # it has to inspect every container (not just the current page) to
    # filter+paginate correctly, which is the expensive part otherwise.
    Rails.cache.fetch("container_resource/#{active_environment&.id}/#{id}", expires_in: 1.hour) do
      detail    = client.container(id)
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
  # Each thread gets its own DockerClient: a single Excon connection isn't
  # safe to share across concurrent threads (that's what actually caused
  # the freeze — not raw Docker daemon latency).
  def fetch_container_resources(ids)
    results  = Concurrent::Hash.new
    endpoint = docker_endpoint
    ids.each_slice(CONCURRENCY) do |batch|
      batch.map { |id| Thread.new { results[id] = fetch_container_resource(id, DockerClient.new(endpoint: endpoint)) } }.each(&:join)
    end
    results
  end

  def infra_status_for(res)
    return "unknown" if res.nil?
    (res[:memory] && res[:cpu]) ? "limited" : "unlimited"
  end

  def sort_containers(containers, sort, dir, resources_cache)
    sorted = case sort
             when "name"
               containers.sort_by { |c| (c["Names"]&.first&.sub(/^\//, "") || c["Id"]).downcase }
             when "status"
               containers.sort_by { |c| c["State"].to_s.downcase }
             when "health"
               containers.sort_by { |c| health_rank(c) }
             when "infra"
               containers.sort_by { |c| infra_status_for(resources_cache[c["Id"]]) }
             else
               containers
             end
    dir == "desc" ? sorted.reverse : sorted
  end

  # Lower rank sorts first (ascending): unhealthy surfaces before healthy
  # so the worst-off containers are visible without flipping direction.
  def health_rank(c)
    raw = c["Status"].to_s
    return 0 if raw.include?("(unhealthy)")
    return 1 if raw.include?("(health: starting)")
    return 2 if raw.include?("(healthy)")
    3
  end
end

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
    redirect_to containers_path(list_filter_params), alert: "Container not found."
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
    @endpoint       = active_environment&.effective_endpoint || "unix:///var/run/docker.sock"
    @exec_user      = params[:root] == "1" ? "root" : params[:user].presence
  rescue DockerClient::NotFoundError
    redirect_to containers_path(list_filter_params), alert: "Container not found."
  end

  def files
    @container_id   = params[:id]
    @container      = current_docker_client.container(@container_id)
    @container_name = @container.dig("Name")&.sub(/^\//, "") || @container_id[0..11]
    @path = sanitize_container_path(params[:path] || "/")
    output = current_docker_client.exec_run_output(@container_id, ["ls", "-la", @path])
    @entries = parse_ls_output(output)
  rescue DockerClient::NotFoundError
    redirect_to containers_path(list_filter_params), alert: "Container not found."
  rescue => e
    @entries = []
    flash.now[:alert] = "Erro ao listar: #{e.message}"
  end

  def files_download
    container_id = params[:id]
    file_path    = sanitize_container_path(params[:path] || "/")
    tar_data     = current_docker_client.container_archive_get(container_id, file_path)
    filename     = File.basename(file_path)
    send_data tar_data, filename: "#{filename}.tar", type: "application/x-tar", disposition: "attachment"
  rescue DockerClient::NotFoundError
    redirect_to container_files_path(params[:id]), alert: "Container not found."
  rescue => e
    redirect_to container_files_path(params[:id], path: File.dirname(params[:path].to_s)), alert: "Erro: #{e.message}"
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

    endpoint = active_environment&.effective_endpoint
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

    # Manual readpartial pump in BOTH directions. IO.copy_stream with the
    # rack.hijack socket as *source* (browser→ttyd) silently forwards nothing —
    # Puma's hijacked IO doesn't satisfy copy_stream's source read path, so
    # keystrokes never reached ttyd and the terminal "accepted no input" while
    # output (ttyd→browser) still flowed. The readpartial loop reads the hijack
    # socket correctly; TCP_NODELAY (set above) keeps per-keystroke latency low.
    # Frames are decoded+logged only when debug is on (?debug=1 / TTYD_DEBUG_LOG).
    log_id = ttyd_debug_log? ? params[:id].to_s[0, 12] : nil
    Rails.logger.info("[ttyd][#{log_id}] session open (user=#{user || '/bin/sh'})") if log_id
    up   = Thread.new { pump(browser, ttyd, log_id, :in)  rescue nil; close_quietly(ttyd) }
    down = Thread.new { pump(ttyd, browser, log_id, :out) rescue nil; close_quietly(browser) }
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
      redirect_to containers_path(list_filter_params), notice: "Container #{action}ed."
    rescue => e
      redirect_to containers_path(list_filter_params), alert: "Error: #{e.message}"
    end
  end

  def remove
    current_docker_client.container_remove(params[:id], force: params[:force].present?)
    AuditLog.record(user: Current.user, action: "container_remove",
                    target_type: "Container", target_id: params[:id],
                    ip_address: request.remote_ip)
    redirect_to containers_path(list_filter_params), notice: "Container removed."
  rescue => e
    redirect_to containers_path(list_filter_params), alert: "Error: #{e.message}"
  end

  def prune
    result = current_docker_client.containers_prune
    count  = (result["ContainersDeleted"] || []).size
    freed  = result.dig("SpaceReclaimed").to_i
    freed_mb = freed > 0 ? " (#{(freed.to_f / 1_048_576).round(1)} MB liberados)" : ""
    AuditLog.record(user: Current.user, action: "containers_prune",
                    metadata: { count: count, space_reclaimed_bytes: freed,
                                deleted: result["ContainersDeleted"] || [] })
    redirect_to containers_path(list_filter_params), notice: "#{count} container(s) parado(s) removido(s).#{freed_mb}"
  rescue => e
    redirect_to containers_path(list_filter_params), alert: "Erro ao limpar containers: #{e.message}"
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
      redirect_to containers_path(list_filter_params), alert: "#{errors.size} error(s): #{errors.first(3).join('; ')}"
    else
      redirect_to containers_path(list_filter_params), notice: "#{action.capitalize}ed #{ids.size} container(s)."
    end
  end

  private

  # Current list filter/search/pagination state, echoed back on every action
  # redirect so stop/start/restart/kill/remove/bulk/prune don't drop the
  # filters the user is monitoring with. The row action links and the bulk
  # form carry these params on the request; here we pass them straight back to
  # containers_path so the reloaded rows frame keeps the same view.
  def list_filter_params
    params.permit(:q, :infra, :sort, :dir, :per_page, :page, statuses: []).to_h.compact_blank
  end

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

  # ── ttyd debug logging ─────────────────────────────────────────────────────
  # Off by default (the pump just relays). Enable per-terminal with ?debug=1
  # (forwarded by the terminal Stimulus controller) or globally with
  # TTYD_DEBUG_LOG=1 to decode+log every ttyd frame both ways, so the input
  # typed in the browser can be compared against what the container's shell
  # echoed/ran.
  def ttyd_debug_log?
    params[:debug] == "1" || ENV["TTYD_DEBUG_LOG"] == "1"
  end

  # Pipe src→dst byte-for-byte (forward first, so any logging never adds latency
  # to the keystroke). When log_id is set (debug on) the WebSocket frames are
  # also decoded and logged; otherwise it's a plain low-latency relay.
  def pump(src, dst, log_id, direction)
    decoder = log_id ? TtydWsDecoder.new : nil
    loop do
      chunk = src.readpartial(16_384)
      dst.write(chunk)
      decoder&.feed(chunk) { |_op, payload| log_ttyd_frame(log_id, direction, payload) }
    end
  rescue EOFError, IOError, Errno::EBADF, Errno::ECONNRESET
    nil
  end

  # ttyd wire protocol: first byte of each payload is the command.
  #   client→server: "0" stdin, "1" resize(JSON), "{" initial auth JSON
  #   server→client: "0" stdout, "1" set-title, "2" set-preferences
  def log_ttyd_frame(log_id, direction, payload)
    return if payload.nil? || payload.empty?
    cmd  = payload[0]
    data = payload.byteslice(1..) || ""

    if direction == :in
      case cmd
      when "0" then Rails.logger.info("[ttyd][#{log_id}][SENT] #{printable(data)}")
      when "1" then Rails.logger.info("[ttyd][#{log_id}][resize] #{data}")
      else          Rails.logger.info("[ttyd][#{log_id}][init] #{printable(payload)}")
      end
    elsif cmd == "0" # only stdout matters for "what the container ran"
      Rails.logger.info("[ttyd][#{log_id}][RAN ] #{printable(data)}")
    end
  end

  # Make bytes log-safe: scrub invalid UTF-8, drop ANSI escape sequences, and
  # render control chars visibly so CR/LF/Ctrl-C are obvious in the log.
  def printable(str)
    str.to_s.dup.force_encoding("UTF-8").scrub("?")
       .gsub(/\e\[[0-9;?]*[ -\/]*[@-~]/, "")
       .gsub(/\e[@-Z\\-_]/, "")
       .gsub("\r", "\\r").gsub("\n", "\\n").gsub("\t", "\\t")
       .gsub(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/) { format("<%02X>", _1.ord) }
       .slice(0, 600)
  end

  def sanitize_container_path(path)
    File.expand_path(path.to_s, "/").then { |p| p.start_with?("/") ? p : "/" }
  end

  def parse_ls_output(output)
    entries = []
    output.each_line do |line|
      line = line.chomp
      next if line.start_with?("total") || line.blank?
      m = line.match(/^([dlrwxst\-]+)\s+\d+\s+\S+\s+\S+\s+(\d+)\s+([\d\-]+ ?[\d:]+|\w+ +\d+ +[\d:]+)\s+(.+)$/)
      next unless m
      perms, size, date, name = m.captures
      next if name.nil? || name =~ /\A\.\.?\z/
      display_name = name.split(" -> ").first.strip
      type = case perms[0]
             when "d" then :directory
             when "l" then :symlink
             else :file
             end
      entries << { name: display_name, type: type, size: size.to_i, modified: date.strip, permissions: perms }
    end
    entries.sort_by { |e| [e[:type] == :directory ? 0 : 1, e[:name].downcase] }
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

require "net/ssh"
require "net/sftp"
require "shellwords"

# File explorer for a VPS host's real filesystem over SFTP — ported from
# redhusky-remote-ssh's SshFilesController. Uses VpsSftpPool (one connection
# per host reused across clicks) for JSON ops, and throwaway connections for
# streaming (download/archive/raw) since an abandoned client mid-stream must
# not wedge the pool.
class VpsFilesController < ApplicationController
  before_action :set_host
  # Split-screen view from the terminal loads this in an iframe — full sidebar
  # layout would nest a second nav inside the pane, so swap to the bare shell.
  layout -> { params[:embed] ? "embed" : "application" }

  MAX_EDIT_BYTES = 1_048_576 # editor/preview loads the whole file into RAM — cap it
  STREAM_CHUNK   = 65_536
  PREVIEWABLE_IMAGE = %w[.png .jpg .jpeg .gif .svg .webp].freeze

  # The HTML render seeds the first listing into the page. It used to render a
  # bare shell and let the JS fetch this same action as JSON on connect, which
  # cost a second round trip *plus* the Stimulus boot between them — ~230ms of
  # blank pane on top of the frame fetch. The terminal's split-screen prefetches
  # this frame on hover and keeps it for the life of the page, so paying the
  # SSH cost here is paid before the click lands, not after it.
  #
  # Best effort: if the host is unreachable the page still renders and the JS
  # falls back to fetching (and surfacing the error) on connect.
  def index
    respond_to do |format|
      format.html do
        @seed = listing(params[:path].presence) rescue nil
      end
      format.json do
        render json: listing(params[:path].presence)
      rescue => e
        render json: { error: e.message }, status: :unprocessable_entity
      end
    end
  end

  # Streams the file straight from SFTP into the response body — no Tempfile.
  def download
    path = sanitize_path(params[:path])
    slot = VpsStreamThrottle.acquire
    if slot.nil?
      return redirect_to vps_root,
                         alert: "Muitos downloads simultâneos — tente de novo em alguns segundos."
    end

    size = nil
    VpsSftpPool.with(@host) { |sftp| size = sftp.stat!(path).size }

    response.set_header("Content-Length", size.to_s) if size
    send_stream_headers(File.basename(path))
    self.response_body = sftp_stream_enumerator(path, slot: slot)
    slot = nil # a partir daqui quem devolve o slot é o enumerator
    audit_file_action("vps_files.download", path)
  rescue => e
    VpsStreamThrottle.release(slot) # só devolve se o enumerator ainda não assumiu
    reset_stream_headers
    redirect_to vps_root, alert: "Download falhou: #{e.message}"
  end

  # Inline preview (image) — same stream as download, no attachment disposition.
  def raw
    path = sanitize_path(params[:path])
    ext  = File.extname(path).downcase
    raise ArgumentError, "Tipo não suportado para preview" unless PREVIEWABLE_IMAGE.include?(ext)

    response.set_header("Content-Type", Rack::Mime.mime_type(ext, "application/octet-stream"))
    response.set_header("Cache-Control", "private, max-age=300")
    # ponytail: pooled (not throwaway) connection — grid view fires one raw
    # request per thumbnail, and a throwaway Net::SFTP.start per image opened
    # N simultaneous SSH handshakes, starving every Puma thread (incl. /up
    # healthcheck) and getting the container killed as unhealthy. Files here
    # are capped to small previewable images, so serializing them on the
    # pool's per-host mutex is cheap — unlike download/archive, which stay on
    # throwaway connections because a large abandoned transfer would wedge it.
    self.response_body = pooled_stream_enumerator(path)
  rescue => e
    head :unprocessable_entity
  end

  # Folder/multi-file download: tar.gz built on the remote host, streamed
  # through. Accepts either a single :path or multiple :paths[] — a bulk
  # selection is always siblings in the same parent directory.
  def archive
    paths  = Array(params[:paths]).presence || [params[:path]]
    paths  = paths.map { |p| sanitize_path(p) }
    parent = File.dirname(paths.first)
    names  = paths.map { |p| File.basename(p) }
    label  = names.size == 1 ? names.first : "vps-files-#{Time.now.to_i}"

    slot = VpsStreamThrottle.acquire
    if slot.nil?
      return redirect_to vps_root,
                         alert: "Muitos downloads simultâneos — tente de novo em alguns segundos."
    end

    send_stream_headers("#{label}.tar.gz", type: "application/gzip")
    cmd = "tar -czf - -C #{Shellwords.escape(parent)} -- " + names.map { |n| Shellwords.escape(n) }.join(" ")
    self.response_body = Enumerator.new do |y|
      begin
        Net::SSH.start(@host.hostname, @host.username, **VpsSshService.build_options(@host, VpsHostKeyVerifier.new(@host))) do |ssh|
          ssh.open_channel do |ch|
            ch.exec(cmd) do |_, success|
              raise "Could not start tar" unless success
              ch.on_data { |_, d| y << d }
              ch.on_extended_data { |_, _, _d| } # tar warnings — ignore, exit status decides
            end
          end
          ssh.loop
        end
      ensure
        VpsStreamThrottle.release(slot)
      end
    end
    slot = nil # daqui em diante o enumerator devolve
    audit_file_action("vps_files.archive", paths.join(", "))
  rescue => e
    VpsStreamThrottle.release(slot)
    reset_stream_headers
    redirect_to vps_root, alert: "Archive falhou: #{e.message}"
  end

  def upload
    dir = sanitize_path(params[:path] || "/")
    uploaded = params[:files] || []
    results = Array(uploaded).map do |file|
      dest = "#{dir}/#{File.basename(file.original_filename).gsub(/[^\w.\-]/, "_")}"
      sftp_operation { |sftp| sftp.upload!(file.path, dest) }
      { name: file.original_filename, status: "ok" }
    rescue => e
      { name: file.original_filename, status: "error", message: e.message }
    end
    audit_file_action("vps_files.upload", dir)
    render json: results
  end

  def rename
    old_path = sanitize_path(params[:path])
    new_name = params[:name].to_s.gsub(/[\/\0]/, "")
    new_path = "#{File.dirname(old_path)}/#{new_name}"
    sftp_operation { |sftp| sftp.rename!(old_path, new_path) }
    audit_file_action("vps_files.rename", "#{old_path} -> #{new_path}")
    render json: { ok: true, new_path: new_path }
  rescue => e
    render json: { ok: false, error: e.message }, status: :unprocessable_entity
  end

  def permissions
    path = sanitize_path(params[:path])
    mode = params[:mode].to_i(8)
    sftp_operation { |sftp| sftp.setstat!(path, permissions: mode) }
    render json: { ok: true }
  rescue => e
    render json: { ok: false, error: e.message }, status: :unprocessable_entity
  end

  def destroy
    paths = Array(params[:paths]).presence || [params[:path]]
    paths.map { |p| sanitize_path(p) }.each do |path|
      raise ArgumentError, "Refusing to delete /" if path == "/"
      stat = nil
      sftp_operation { |sftp| stat = sftp.stat!(path) }
      if stat.directory?
        # One remote command instead of one SFTP round-trip per descendant.
        ssh_exec!("rm -rf -- #{Shellwords.escape(path)}")
      else
        sftp_operation { |sftp| sftp.remove!(path) }
      end
    end
    audit_file_action("vps_files.delete", paths.join(", "))
    render json: { ok: true }
  rescue => e
    render json: { ok: false, error: e.message }, status: :unprocessable_entity
  end

  def mkdir
    dir = sanitize_path(params[:path])
    name = params[:name].to_s.gsub(/[\/\0]/, "")
    sftp_operation { |sftp| sftp.mkdir!("#{dir}/#{name}") }
    render json: { ok: true }
  rescue => e
    render json: { ok: false, error: e.message }, status: :unprocessable_entity
  end

  # Move (cut + paste): relocate source into the dest directory, same basename.
  def move
    src      = sanitize_path(params[:path])
    dest_dir = sanitize_path(params[:dest])
    target   = join_path(dest_dir, File.basename(src))
    raise ArgumentError, "Destination is the same folder" if File.dirname(src) == dest_dir
    raise ArgumentError, "Cannot move a folder into itself" if target == src || target.start_with?("#{src}/")
    ssh_exec!("mv -- #{Shellwords.escape(src)} #{Shellwords.escape(target)}")
    render json: { ok: true, path: target }
  rescue => e
    render json: { ok: false, error: e.message }, status: :unprocessable_entity
  end

  # Copy (copy + paste): recursive copy into the dest directory via `cp -a`
  # over SSH — SFTP has no copy primitive.
  def copy
    src      = sanitize_path(params[:path])
    dest_dir = sanitize_path(params[:dest])
    target   = join_path(dest_dir, File.basename(src))
    raise ArgumentError, "Cannot copy a folder into itself" if target.start_with?("#{src}/")
    if target == src # pasting into the same folder — keep both
      ext    = File.extname(src)
      target = join_path(dest_dir, "#{File.basename(src, ext)}-copy#{ext}")
    end
    ssh_exec!("cp -a -- #{Shellwords.escape(src)} #{Shellwords.escape(target)}")
    render json: { ok: true, path: target }
  rescue => e
    render json: { ok: false, error: e.message }, status: :unprocessable_entity
  end

  def content
    path = sanitize_path(params[:path])
    data = nil
    sftp_operation do |sftp|
      size = sftp.stat!(path).size.to_i
      raise ArgumentError, "Arquivo grande demais (#{(size / 1_048_576.0).round(1)} MB, limite 1 MB) — use download" if size > MAX_EDIT_BYTES
      data = sftp.download!(path)
    end
    data = data.to_s
    render json: { content: data.dup.force_encoding("UTF-8"), size: data.bytesize }
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update_content
    path = sanitize_path(params[:path])
    content = params[:content].to_s
    sftp_operation { |sftp| sftp.file.open(path, "w") { |f| f.write(content) } }
    audit_file_action("vps_files.edit", path)
    render json: { ok: true }
  rescue => e
    render json: { ok: false, error: e.message }, status: :unprocessable_entity
  end

  private

  def set_host
    @host = VpsHost.find(params[:vps_host_id])
  end

  def sftp_operation(&block)
    VpsSftpPool.with(@host, &block)
  end

  def ssh_exec!(command)
    out = +""
    err = +""
    status = nil
    VpsSftpPool.with_ssh(@host) do |ssh|
      ch = ssh.open_channel do |channel|
        channel.exec(command) do |_, success|
          raise "Could not execute command" unless success
          channel.on_data { |_, d| out << d }
          channel.on_extended_data { |_, _, d| err << d }
          channel.on_request("exit-status") { |_, data| status = data.read_long }
        end
      end
      ch.wait
    end
    raise(err.strip.presence || "Command failed (exit #{status})") unless status == 0
    out
  end

  # Reads the whole file inside the pool's mutex (thumbnails are small,
  # capped to PREVIEWABLE_IMAGE) so the SSH connection is held only for the
  # actual transfer, not for however long the client takes to consume it.
  # Redis-cached per host+path+mtime — grid view re-fetches the same
  # thumbnails on every open/scroll, no need to hit SFTP each time.
  def pooled_stream_enumerator(path)
    mtime = VpsSftpPool.with(@host) { |sftp| sftp.stat!(path).mtime }
    data = Rails.cache.fetch([ "vps_raw", @host.id, path, mtime ], expires_in: 1.hour) do
      VpsSftpPool.with(@host) { |sftp| sftp.download!(path) }
    end
    [ data ]
  end

  # O slot é tomado na action (antes de qualquer header) e devolvido aqui,
  # quando o corpo termina de ser consumido ou o cliente desiste.
  def sftp_stream_enumerator(path, slot: nil)
    Enumerator.new do |y|
      begin
        Net::SFTP.start(@host.hostname, @host.username, **VpsSshService.build_options(@host, VpsHostKeyVerifier.new(@host))) do |sftp|
          sftp.file.open(path, "r") do |f|
            while (chunk = f.read(STREAM_CHUNK))
              y << chunk
            end
          end
        end
      ensure
        VpsStreamThrottle.release(slot)
      end
    end
  end

  def audit_file_action(action, path)
    AuditLog.record(user: Current.user, action: action, target_type: "VpsHost", target_id: @host.id,
                     metadata: { path: path }, ip_address: request.remote_ip)
  end

  def send_stream_headers(filename, type: "application/octet-stream")
    response.set_header("Content-Type", type)
    response.set_header("Content-Disposition",
                        ActionDispatch::Http::ContentDisposition.format(disposition: "attachment", filename: filename))
    response.set_header("Cache-Control", "no-store")
    response.set_header("Last-Modified", Time.now.httpdate)
  end

  def reset_stream_headers
    response.headers.delete("Content-Disposition")
    response.headers.delete("Content-Length")
  end

  def join_path(dir, name)
    "#{dir}/#{name}".gsub(%r{/+}, "/")
  end

  def listing(requested)
    sftp_operation do |sftp|
      path = requested ? sanitize_path(requested) : resolve_home(sftp)
      { path: path, entries: list_directory(sftp, path) }
    end
  end

  def list_directory(sftp, path)
    sftp.dir.entries(path).filter_map do |entry|
      next if %w[. ..].include?(entry.name)
      {
        name: entry.name,
        path: "#{path}/#{entry.name}".gsub("//", "/"),
        type: entry.directory? ? "directory" : "file",
        size: entry.attributes.size,
        modified: entry.attributes.mtime ? Time.at(entry.attributes.mtime) : nil,
        permissions: entry.attributes.permissions
      }
    end.sort_by { |e| [e[:type] == "directory" ? 0 : 1, e[:name].downcase] }
  end

  def resolve_home(sftp)
    sftp.realpath!(".").name.presence || sftp_home
  rescue
    sftp_home
  end

  def sftp_home
    @host.username == "root" ? "/root" : "/home/#{@host.username}"
  end

  def sanitize_path(path)
    cleaned = File.expand_path(path.to_s.gsub("\0", ""), "/")
    raise ArgumentError, "Invalid path" unless cleaned.start_with?("/")
    cleaned
  end

  def vps_root
    vps_host_files_path(@host)
  end
end

class VolumesController < ApplicationController
  include DockerCache
  before_action :require_operator!, only: %i[remove batch_remove upload file_delete file_mkdir file_rename]

  # Image used for ephemeral containers when no running container has the volume mounted.
  HELPER_IMAGE = "busybox:latest".freeze

  # remove/batch_remove redirect back here from inside the lazy
  # turbo-frame (volumes-content) — same self-referential nested-frame
  # bug fixed for ContainersController et al.
  def index
    rows if turbo_frame_request?
  end

  def rows
    vols_result = nil
    df_result   = nil

    endpoint = docker_endpoint
    t1 = Thread.new { vols_result = DockerClient.new(endpoint: endpoint).volumes["Volumes"] || [] rescue [] }
    t2 = Thread.new { df_result   = cached_system_df("volume") rescue {} }
    t1.join; t2.join

    df_map = ((df_result["Volumes"] rescue nil) || []).each_with_object({}) do |v, h|
      h[v["Name"]] = { size: v.dig("UsageData", "Size").to_i, refs: v.dig("UsageData", "RefCount").to_i }
    end
    @volumes = vols_result.map { |v| v.merge("_size" => df_map.dig(v["Name"], :size).to_i, "_refs" => df_map.dig(v["Name"], :refs)) }
    render "rows", layout: false
  rescue => e
    @volumes = []
    render "rows", layout: false
  end

  def show
    redirect_to volumes_path
  end

  def browse
    @volume_name = params[:id]
    @path = sanitize_path(params[:path] || "/")
    with_volume_container(@volume_name) do |container_id, mountpoint|
      @container_id = container_id
      @mountpoint   = mountpoint
      full_path = join_path(mountpoint, @path)
      output = current_docker_client.exec_run_output(container_id, ["ls", "-la", full_path]) rescue ""
      @entries = parse_ls_output(output)
    end
    @entries ||= []
  rescue => e
    @entries = []
    flash.now[:alert] = "Erro ao listar: #{e.message}"
  end

  def download
    vol_name  = params[:id]
    file_path = sanitize_path(params[:path] || "/")
    with_volume_container(vol_name) do |container_id, mountpoint|
      full_path = join_path(mountpoint, file_path)
      tar_data  = current_docker_client.container_archive_get(container_id, full_path)
      filename  = File.basename(file_path)
      send_data tar_data, filename: "#{filename}.tar", type: "application/x-tar", disposition: "attachment"
      return
    end
    redirect_to browse_volume_path(vol_name, path: File.dirname(file_path)), alert: "Volume inacessível."
  rescue => e
    redirect_to browse_volume_path(params[:id], path: File.dirname(params[:path].to_s)), alert: "Erro: #{e.message}"
  end

  def upload
    vol_name  = params[:id]
    dest_path = sanitize_path(params[:path] || "/")
    file      = params[:file]
    return redirect_to(browse_volume_path(vol_name, path: dest_path), alert: "Nenhum arquivo selecionado.") unless file
    with_volume_container(vol_name) do |container_id, mountpoint|
      full_dest = join_path(mountpoint, dest_path)
      tar_data  = build_tar(file.original_filename, file.read)
      current_docker_client.container_archive_put(container_id, full_dest, tar_data)
      redirect_to browse_volume_path(vol_name, path: dest_path), notice: "\"#{file.original_filename}\" enviado."
      return
    end
    redirect_to browse_volume_path(vol_name, path: dest_path), alert: "Volume inacessível."
  rescue => e
    redirect_to browse_volume_path(vol_name, path: dest_path), alert: "Erro: #{e.message}"
  end

  def file_delete
    vol_name  = params[:id]
    file_path = sanitize_path(params[:path])
    return redirect_to(browse_volume_path(vol_name), alert: "Caminho inválido.") if file_path == "/"
    with_volume_container(vol_name) do |container_id, mountpoint|
      full_path = join_path(mountpoint, file_path)
      current_docker_client.exec_run_output(container_id, ["rm", "-rf", "--", full_path])
      redirect_to browse_volume_path(vol_name, path: File.dirname(file_path)), notice: "\"#{File.basename(file_path)}\" removido."
      return
    end
    redirect_to browse_volume_path(vol_name), alert: "Volume inacessível."
  rescue => e
    redirect_to browse_volume_path(vol_name), alert: "Erro: #{e.message}"
  end

  def file_mkdir
    vol_name  = params[:id]
    parent    = sanitize_path(params[:path] || "/")
    dir_name  = params[:dir_name].to_s.gsub(/[\/\0]/, "").strip
    return redirect_to(browse_volume_path(vol_name, path: parent), alert: "Nome inválido.") if dir_name.blank?
    with_volume_container(vol_name) do |container_id, mountpoint|
      full_path = join_path(mountpoint, parent, dir_name)
      current_docker_client.exec_run_output(container_id, ["mkdir", "-p", "--", full_path])
      redirect_to browse_volume_path(vol_name, path: parent), notice: "Diretório \"#{dir_name}\" criado."
      return
    end
    redirect_to browse_volume_path(vol_name, path: parent), alert: "Volume inacessível."
  rescue => e
    redirect_to browse_volume_path(vol_name, path: params[:path].to_s), alert: "Erro: #{e.message}"
  end

  def file_rename
    vol_name = params[:id]
    old_path = sanitize_path(params[:path])
    new_name = params[:new_name].to_s.gsub(/[\/\0]/, "").strip
    parent   = File.dirname(old_path)
    return redirect_to(browse_volume_path(vol_name, path: parent), alert: "Nome inválido.") if new_name.blank?
    with_volume_container(vol_name) do |container_id, mountpoint|
      old_full = join_path(mountpoint, old_path)
      new_full = join_path(mountpoint, parent, new_name)
      current_docker_client.exec_run_output(container_id, ["mv", "--", old_full, new_full])
      redirect_to browse_volume_path(vol_name, path: parent), notice: "Renomeado para \"#{new_name}\"."
      return
    end
    redirect_to browse_volume_path(vol_name, path: parent), alert: "Volume inacessível."
  rescue => e
    redirect_to browse_volume_path(params[:id], path: File.dirname(params[:path].to_s)), alert: "Erro: #{e.message}"
  end

  def remove
    current_docker_client.volume_remove(params[:id], force: params[:force].present?)
    redirect_to volumes_path, notice: "Volume removido."
  rescue => e
    redirect_to volumes_path, alert: "Error: #{e.message}"
  end

  def batch_remove
    names  = Array(params[:names])
    errors = []
    names.each do |name|
      current_docker_client.volume_remove(name, force: true)
    rescue => e
      errors << e.message
    end
    removed = names.size - errors.size
    if errors.any?
      redirect_to volumes_path, alert: "#{removed} removido(s). Erros: #{errors.first(3).join('; ')}"
    else
      redirect_to volumes_path, notice: "#{removed} volume(s) removido(s)."
    end
  end

  private

  # Yields [container_id, mountpoint] for the volume.
  # If a running container has it mounted → use that.
  # Otherwise → spin up a temp busybox container, yield, then remove it.
  def with_volume_container(vol_name, &block)
    # Try running containers first
    containers = current_docker_client.containers(all: false)
    containers.each do |c|
      c["Mounts"]&.each do |m|
        if m["Name"] == vol_name || m["Source"]&.end_with?("/#{vol_name}/_data")
          block.call(c["Id"], m["Destination"])
          return
        end
      end
    end

    # No running container — create ephemeral one
    mountpoint = "/mnt/vol"
    tmp_name   = "redhusk-vol-#{vol_name.gsub(/[^a-zA-Z0-9_-]/, "-").first(40)}-#{SecureRandom.hex(4)}"
    resp = begin
      create_helper_container(tmp_name, vol_name, mountpoint)
    rescue DockerClient::NotFoundError
      # Helper image not pulled on this host yet — pull once and retry.
      current_docker_client.image_pull(HELPER_IMAGE.split(":").first, tag: HELPER_IMAGE.split(":").last)
      create_helper_container(tmp_name, vol_name, mountpoint)
    end
    tmp_id = resp["Id"] || resp.is_a?(Hash) && resp["Id"]
    raise "Falha ao criar container temporário" unless tmp_id

    current_docker_client.container_start(tmp_id)
    begin
      block.call(tmp_id, mountpoint)
    ensure
      current_docker_client.container_remove(tmp_id, force: true) rescue nil
    end
  rescue DockerClient::Error => e
    raise "Não foi possível acessar o volume: #{e.message}"
  end

  def create_helper_container(tmp_name, vol_name, mountpoint)
    current_docker_client.container_create(
      name:   tmp_name,
      image:  HELPER_IMAGE,
      binds:  ["#{vol_name}:#{mountpoint}"],
      cmd:    ["sh", "-c", "tail -f /dev/null"]
    )
  end

  def sanitize_path(path)
    File.expand_path(path.to_s, "/").then { |p| p.start_with?("/") ? p : "/" }
  end

  def join_path(*parts)
    File.join(*parts).gsub(%r{/+}, "/")
  end

  def parse_ls_output(output)
    entries = []
    output.each_line do |line|
      line = line.chomp
      next if line.start_with?("total") || line.blank?
      if (m = line.match(/^([dlrwxst\-]+)\s+\d+\s+\S+\s+\S+\s+(\d+)\s+(\d{4}-\d{2}-\d{2} \d{2}:\d{2})\s+(.+)$/))
        perms, size, date, name = m.captures
      elsif (m = line.match(/^([dlrwxst\-]+)\s+\d+\s+\S+\s+\S+\s+(\d+)\s+(\w+\s+\d+\s+[\d:]+)\s+(.+)$/))
        perms, size, date, name = m.captures
      else
        next
      end
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

  def build_tar(filename, data)
    require "rubygems/package"
    io = StringIO.new("".b)
    Gem::Package::TarWriter.new(io) do |tar|
      tar.add_file_simple(filename, 0o644, data.bytesize) { |f| f.write(data) }
    end
    io.string
  end
end

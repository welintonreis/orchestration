class ImagesController < ApplicationController
  before_action :require_operator!, only: %i[remove batch_remove prune_orphans]

  # remove/batch_remove/prune_orphans redirect back here from inside the
  # lazy turbo-frame (images-content) — same self-referential nested-frame
  # bug fixed for ContainersController et al: a Turbo-Frame-header redirect
  # rendering the skeleton+nested lazy-frame shell never re-fires the
  # follow-up fetch. Render rows directly instead.
  def index
    rows if turbo_frame_request?
  end

  def rows
    images_result    = nil
    containers_result = nil

    endpoint = docker_endpoint
    client = DockerClient.new(endpoint: endpoint)
    t1 = Thread.new { images_result    = client.images }
    t2 = Thread.new { containers_result = client.containers(all: true) rescue [] }
    t1.join
    t2.join

    usage_map = (containers_result || []).each_with_object(Hash.new(0)) { |c, h| h[c["ImageID"]] += 1 if c["ImageID"] }
    @images = (images_result || []).map do |img|
      containers_count = usage_map[img["Id"]].to_i
      dangling = img["RepoTags"].nil? || img["RepoTags"] == ["<none>:<none>"]
      img.merge("_containers" => containers_count, "_dangling" => dangling, "_unused" => containers_count == 0)
    end
    render "rows", layout: false
  rescue => e
    @images = []
    render "rows", layout: false
  end

  def show
    @image   = current_docker_client.image(params[:id])
    @history = current_docker_client.image_history(params[:id]) rescue []
  rescue DockerClient::NotFoundError
    redirect_to images_path, alert: "Image not found."
  end

  def remove
    current_docker_client.image_remove(params[:id], force: params[:force].present?)
    redirect_to images_path, notice: "Image removed."
  rescue => e
    redirect_to images_path, alert: "Error: #{e.message}"
  end

  def batch_remove
    ids    = Array(params[:ids])
    errors = []
    ids.each do |id|
      current_docker_client.image_remove(id, force: true)
    rescue => e
      errors << e.message
    end
    removed = ids.size - errors.size
    if errors.any?
      redirect_to images_path, alert: "#{removed} removida(s). Erros: #{errors.first(3).join('; ')}"
    else
      redirect_to images_path, notice: "#{removed} imagem(ns) removida(s)."
    end
  end

  def prune_orphans
    result = current_docker_client.images_prune
    freed  = result.dig("SpaceReclaimed").to_i
    count  = (result["ImagesDeleted"] || []).size
    freed_mb = freed > 0 ? " (#{(freed.to_f / 1_048_576).round(1)} MB liberados)" : ""
    redirect_to images_path, notice: "#{count} imagem(ns) órfã(s) removida(s).#{freed_mb}"
  rescue => e
    redirect_to images_path, alert: "Erro ao limpar órfãos: #{e.message}"
  end
end

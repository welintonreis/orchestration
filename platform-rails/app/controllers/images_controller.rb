class ImagesController < ApplicationController
  before_action :require_operator!, only: %i[remove batch_remove prune_orphans]

  def index
  end

  def rows
    images_result = nil
    df_result     = nil

    t1 = Thread.new { images_result = current_docker_client.images }
    t2 = Thread.new { df_result     = cached_system_df("image") rescue {} }
    t1.join
    t2.join

    df_map = ((df_result || {})["Images"] || []).each_with_object({}) { |img, h| h[img["Id"]] = img["Containers"].to_i }
    @images = (images_result || []).map do |img|
      containers_count = df_map[img["Id"]].to_i
      dangling = img["RepoTags"].nil? || img["RepoTags"] == ["<none>:<none>"]
      img.merge("_containers" => containers_count, "_dangling" => dangling, "_unused" => containers_count == 0)
    end
    render layout: false
  rescue => e
    @images = []
    render layout: false
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

  private

  # Docker's /system/df is expensive (walks every image's layers to
  # compute usage), so cache it briefly instead of recomputing on every
  # filter/per-page change in the rows turbo-frame.
  def cached_system_df(type)
    Rails.cache.fetch("docker_system_df/#{type}/#{active_environment&.id}", expires_in: 20.seconds) do
      current_docker_client.system_df(type: type)
    end
  end
end

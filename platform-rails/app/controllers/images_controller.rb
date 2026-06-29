class ImagesController < ApplicationController
  before_action :require_operator!, only: %i[remove batch_remove prune_orphans pull]

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
    all_images = (images_result || []).map do |img|
      containers_count = usage_map[img["Id"]].to_i
      dangling = img["RepoTags"].nil? || img["RepoTags"] == ["<none>:<none>"]
      img.merge("_containers" => containers_count, "_dangling" => dangling, "_unused" => containers_count == 0)
    end

    # Search needs to run against every image before pagination, same as
    # containers — otherwise it'd only filter whatever page is currently
    # rendered. Images don't have a single "name" — match against any repo
    # tag or the image id.
    @query = params[:q].to_s.strip
    if @query.present?
      q = @query.downcase
      all_images = all_images.select do |img|
        tags = Array(img["RepoTags"])
        tags.any? { |t| t.to_s.downcase.include?(q) } || img["Id"].to_s.downcase.start_with?(q)
      end
    end

    # Group first (same logic as view) so pagination counts repos, not individual
    # image layers — otherwise 10 images from 3 repos shows only 3 visible rows.
    all_grouped = all_images.group_by do |img|
      raw = (img["RepoTags"] || []).first || "<none>:<none>"
      raw == "<none>:<none>" ? "<none>" : raw.split(":")[0..-2].join(":")
    end.sort_by { |repo, _| repo }

    @total_images = all_images.size
    @total        = all_grouped.size   # pagination unit = repos
    @per_page     = params[:per_page] == "0" ? nil : (params[:per_page]&.to_i || 10)
    @page         = [params[:page]&.to_i || 1, 1].max

    if @per_page
      @total_pages    = [(@total.to_f / @per_page).ceil, 1].max
      @page           = [@page, @total_pages].min
      paginated_groups = all_grouped.drop((@page - 1) * @per_page).first(@per_page)
    else
      @total_pages    = 1
      paginated_groups = all_grouped
    end

    @images = paginated_groups.flat_map { |_, imgs| imgs }

    render "rows", layout: false
  rescue => e
    @images = []
    @total = @page = @total_pages = 0
    @per_page = 10
    @query = ""
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

  def search
    @registries = SwarmRegistry.public_registries.searchable.order(:name)
    @registry   = @registries.find_by(id: params[:registry_id]) || @registries.first
    @query      = params[:q].to_s.strip
    @results    = @registry && @query.present? ? RegistrySearchService.call(@registry, @query) : []
    render layout: false
  end

  def pull
    image    = params[:image].to_s.strip
    tag      = params[:tag].to_s.strip.presence || "latest"
    redirect_to(images_path, alert: "Nome da imagem inválido.") and return if image.blank? || image.include?(" ")

    ImagePullJob.perform_later(
      image:    image,
      tag:      tag,
      user_id:  Current.user&.id,
      endpoint: docker_endpoint
    )
    redirect_to images_path, notice: "Pull de #{image}:#{tag} iniciado em background — acompanhe nos logs de auditoria."
  end
end

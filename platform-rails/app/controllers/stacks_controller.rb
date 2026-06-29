class StacksController < ApplicationController
  # scale_service/drain_stack_service redirect back here from inside the
  # lazy turbo-frame (stacks-content) — same self-referential nested-frame
  # bug fixed for ContainersController/Swarm::ServicesController: a
  # Turbo-Frame-header redirect rendering the skeleton+nested lazy-frame
  # shell never re-fires the follow-up fetch. Render rows directly instead.
  def index
    rows if turbo_frame_request?
  end

  def rows
    all_services = current_docker_client.services rescue []
    @nodes       = current_docker_client.nodes    rescue []
    all_stacks = all_services
      .group_by { |s| s.dig("Spec", "Labels", "com.docker.stack.namespace") }
      .reject    { |ns, _| ns.nil? }
      .map do |ns, svcs|
        active = svcs.any? { |s| s.dig("ServiceStatus", "RunningTasks").to_i > 0 }
        {
          "Name"        => ns,
          "Services"    => svcs.size,
          "Orchestrator"=> "Swarm",
          "CreatedAt"   => svcs.map { |s| s["CreatedAt"] }.min,
          "ServiceList" => svcs,
          "Active"      => active
        }
      end
      .sort_by { |s| s["Name"] }

    # Search needs to run against every stack (and the service names inside
    # it) before pagination, same as containers — otherwise it'd only
    # filter whatever page is currently rendered. A stack matches if its own
    # name matches, or any of its services' names match.
    @query = params[:q].to_s.strip
    if @query.present?
      q = @query.downcase
      all_stacks = all_stacks.select do |stack|
        stack["Name"].to_s.downcase.include?(q) ||
          stack["ServiceList"].any? { |svc| (svc.dig("Spec", "Name") || "").downcase.include?(q) }
      end
    end

    @git_stacks   = GitStack.includes(:environment).order(:name)
    @total        = all_stacks.size
    @active_total = all_stacks.count { |s| s["Active"] }
    @per_page = params[:per_page] == "0" ? nil : (params[:per_page]&.to_i || 10)
    @page     = [params[:page]&.to_i || 1, 1].max
    if @per_page
      @total_pages = [(@total.to_f / @per_page).ceil, 1].max
      @page        = [@page, @total_pages].min
      @stacks      = all_stacks.drop((@page - 1) * @per_page).first(@per_page)
    else
      @total_pages = 1
      @stacks      = all_stacks
    end

    render "rows", layout: false
  rescue => e
    @stacks = []
    @nodes  = []
    @git_stacks   = GitStack.includes(:environment).order(:name) rescue []
    @total = @page = @total_pages = @active_total = 0
    @per_page = 10
    @query = ""
    render "rows", layout: false
  end

  # Triggered by the scale/drain forms living inside the stacks-content
  # turbo-frame (per-service rows), which redirect back to this same
  # index — a Turbo-Frame redirect to #index renders "rows" with
  # layout: false (see above), so shared/_flash (only rendered by the full
  # layout) never displays the notice/alert and Rails never sweeps it from
  # the session: the message silently survives into the next unrelated
  # full-page navigation. Render rows directly instead, using flash.now so
  # this same response shows it.
  def scale_service
    replicas = params[:replicas].to_i
    current_docker_client.service_scale(params[:service_id], replicas)
    render_stacks_flash(notice: "Serviço escalado para #{replicas} réplica(s)")
  rescue => e
    render_stacks_flash(alert: "Erro ao escalar: #{e.message}")
  end

  def drain_stack_service
    current_docker_client.service_scale(params[:service_id], 0)
    render_stacks_flash(notice: "Serviço desidratado (0 réplicas)")
  rescue => e
    render_stacks_flash(alert: "Erro ao desidratar: #{e.message}")
  end

  private

  def render_stacks_flash(notice: nil, alert: nil)
    if turbo_frame_request?
      flash.now[:notice] = notice if notice
      flash.now[:alert]  = alert  if alert
      rows
    else
      redirect_to stacks_path, notice: notice, alert: alert
    end
  end
end

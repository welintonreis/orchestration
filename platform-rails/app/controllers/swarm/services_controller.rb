module Swarm
  class ServicesController < ApplicationController
    include SwarmGuard

    # Drain/rollback/scale redirect back here from inside the lazy
    # turbo-frame (services-content), so the redirect's follow-up GET
    # carries the same Turbo-Frame header — rendering the skeleton+nested
    # lazy-frame shell in response to that (same self-referential frame
    # bug fixed for ContainersController) just showed the skeleton forever
    # with no follow-up fetch. Render rows content directly instead.
    def index
      rows if turbo_frame_request?
    end

    def rows
      all_services = current_docker_client.services
      @nodes       = current_docker_client.nodes

      @query = params[:q].to_s.strip
      if @query.present?
        q = @query.downcase
        all_services = all_services.select do |s|
          name  = (s.dig("Spec", "Name") || "").downcase
          image = (s.dig("Spec", "TaskTemplate", "ContainerSpec", "Image") || "").split("@").first.downcase
          name.include?(q) || image.include?(q)
        end
      end

      @total    = all_services.size
      @per_page = params[:per_page] == "0" ? nil : (params[:per_page]&.to_i || 25)
      @page     = [params[:page]&.to_i || 1, 1].max
      if @per_page
        @total_pages = [(@total.to_f / @per_page).ceil, 1].max
        @page        = [@page, @total_pages].min
        @services    = all_services.drop((@page - 1) * @per_page).first(@per_page)
      else
        @total_pages = 1
        @services    = all_services
      end

      render "rows", layout: false
    rescue => e
      @services    = []
      @nodes       = []
      @total       = 0
      @page        = 1
      @total_pages = 1
      @per_page    = 25
      @query       = ""
      render "rows", layout: false
    end

    def show
      @service = current_docker_client.service(params[:id])
      @tasks   = current_docker_client.service_tasks(params[:id])
                   .sort_by { |t| -(Time.parse(t["UpdatedAt"]).to_f rescue 0.0) }
      @nodes   = current_docker_client.nodes.index_by { |n| n["ID"] }
      @max_cpu = [@nodes.values.sum { |n| n.dig("Description", "Resources", "NanoCPUs").to_f / 1_000_000_000 }.ceil, 1].max
    rescue => e
      redirect_to swarm_services_path, alert: "Serviço não encontrado: #{e.message}"
    end

    def update_resources
      cpu_limit_nano = (params[:cpu_limit].to_f * 1_000_000_000).to_i
      cpu_res_nano   = (params[:cpu_res].to_f   * 1_000_000_000).to_i
      mem_limit      = params[:mem_limit_mb].to_i * 1_048_576
      mem_res        = params[:mem_res_mb].to_i   * 1_048_576

      current_docker_client.service_update(params[:id]) do |spec|
        res = (spec["TaskTemplate"]["Resources"] ||= {})
        (res["Limits"]       ||= {}).merge!("NanoCPUs" => cpu_limit_nano, "MemoryBytes" => mem_limit)
        (res["Reservations"] ||= {}).merge!("NanoCPUs" => cpu_res_nano,   "MemoryBytes" => mem_res)
      end
      redirect_to swarm_service_path(params[:id]), notice: "Resources atualizados"
    rescue => e
      redirect_to swarm_service_path(params[:id]), alert: "Erro: #{e.message}"
    end

    def update_update_config
      delay_nano = params[:delay_s].to_i * 1_000_000_000
      current_docker_client.service_update(params[:id]) do |spec|
        uc = (spec["UpdateConfig"] ||= {})
        uc["Parallelism"]   = params[:parallelism].to_i
        uc["Delay"]         = delay_nano
        uc["FailureAction"] = params[:failure_action].presence || "pause"
        uc["Order"]         = params[:order].presence || "stop-first"
      end
      redirect_to swarm_service_path(params[:id]), notice: "Update config salvo"
    rescue => e
      redirect_to swarm_service_path(params[:id]), alert: "Erro: #{e.message}"
    end

    def update_logging
      current_docker_client.service_update(params[:id]) do |spec|
        spec["TaskTemplate"]["LogDriver"] = {
          "Name"    => params[:driver].presence || "json-file",
          "Options" => {}
        }
      end
      redirect_to swarm_service_path(params[:id]), notice: "Logging driver atualizado"
    rescue => e
      redirect_to swarm_service_path(params[:id]), alert: "Erro: #{e.message}"
    end

    def update_image
      image = params[:image].to_s.strip
      return redirect_to(swarm_service_path(params[:id]), alert: "Image não pode ser vazio") if image.blank?

      current_docker_client.service_update(params[:id]) do |spec|
        spec["TaskTemplate"]["ContainerSpec"]["Image"] = image
      end
      redirect_to swarm_service_path(params[:id]), notice: "Image atualizada"
    rescue => e
      redirect_to swarm_service_path(params[:id]), alert: "Erro: #{e.message}"
    end

    def rollback
      current_docker_client.service_rollback(params[:id])
      redirect_to swarm_service_path(params[:id]), notice: "Rollback iniciado"
    rescue => e
      redirect_to swarm_service_path(params[:id]), alert: "Erro no rollback: #{e.message}"
    end

    # scale/drain/bulk_scale are triggered by buttons/forms living inside
    # the services-content turbo-frame (the index's per-row and bulk-action
    # controls), which redirect back to this same index — a Turbo-Frame
    # redirect to #index renders "rows" with layout: false (see above), so
    # shared/_flash (only rendered by the full layout) never displays the
    # notice/alert and Rails never sweeps it from the session: the message
    # silently survives into the next unrelated full-page navigation.
    # Render rows directly instead, using flash.now so this same response
    # shows it. update_resources/update_update_config/update_logging/
    # update_image/rollback above are NOT converted: they're only
    # reachable from #show (a full page, not frame-scoped), so their plain
    # redirect_to is correct as-is.
    def scale
      replicas = params[:replicas].to_i
      current_docker_client.service_scale(params[:id], replicas)
      render_services_flash(notice: "Serviço escalado para #{replicas} réplica(s)")
    rescue => e
      render_services_flash(alert: "Erro ao escalar: #{e.message}")
    end

    def drain
      current_docker_client.service_scale(params[:id], 0)
      render_services_flash(notice: "Serviço desidratado (0 réplicas)")
    rescue => e
      render_services_flash(alert: "Erro ao desidratar: #{e.message}")
    end

    def force_update
      current_docker_client.service_update(params[:id]) do |spec|
        # Strip digest so Swarm re-pulls the tag on next task start
        image = spec.dig("TaskTemplate", "ContainerSpec", "Image").to_s
        spec["TaskTemplate"]["ContainerSpec"]["Image"] = image.split("@").first
        spec["TaskTemplate"]["ForceUpdate"] = spec.dig("TaskTemplate", "ForceUpdate").to_i + 1
      end
      render_services_flash(notice: "Atualização forçada iniciada")
    rescue => e
      render_services_flash(alert: "Erro ao atualizar: #{e.message}")
    end

    def bulk_scale
      ids   = Array(params[:ids])
      delta = params[:delta].to_i
      errors = []
      ids.each do |id|
        svc      = current_docker_client.service(id)
        current  = svc.dig("Spec", "Mode", "Replicated", "Replicas").to_i
        new_reps = [current + delta, 0].max
        current_docker_client.service_scale(id, new_reps)
      rescue => e
        errors << e.message
      end
      sign = delta >= 0 ? "+#{delta}" : delta.to_s
      if errors.any?
        render_services_flash(alert: "Erros: #{errors.first(3).join('; ')}")
      else
        render_services_flash(notice: "#{ids.size} serviço(s) escalado(s) #{sign}.")
      end
    end

    private

    def render_services_flash(notice: nil, alert: nil)
      if turbo_frame_request?
        flash.now[:notice] = notice if notice
        flash.now[:alert]  = alert  if alert
        rows
      else
        redirect_to swarm_services_path, notice: notice, alert: alert
      end
    end
  end
end

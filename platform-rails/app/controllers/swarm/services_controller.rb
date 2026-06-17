module Swarm
  class ServicesController < ApplicationController
    include SwarmGuard

    def index
    end

    def rows
      @services = current_docker_client.services
      @nodes    = current_docker_client.nodes
      render layout: false
    rescue => e
      @services = []
      @nodes    = []
      render layout: false
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

    def scale
      replicas = params[:replicas].to_i
      current_docker_client.service_scale(params[:id], replicas)
      redirect_to swarm_services_path, notice: "Serviço escalado para #{replicas} réplica(s)"
    rescue => e
      redirect_to swarm_services_path, alert: "Erro ao escalar: #{e.message}"
    end

    def drain
      current_docker_client.service_scale(params[:id], 0)
      redirect_to swarm_services_path, notice: "Serviço desidratado (0 réplicas)"
    rescue => e
      redirect_to swarm_services_path, alert: "Erro ao desidratar: #{e.message}"
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
        redirect_to swarm_services_path, alert: "Erros: #{errors.first(3).join('; ')}"
      else
        redirect_to swarm_services_path, notice: "#{ids.size} serviço(s) escalado(s) #{sign}."
      end
    end
  end
end

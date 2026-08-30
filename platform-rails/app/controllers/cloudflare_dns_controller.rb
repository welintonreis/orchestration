# frozen_string_literal: true

class CloudflareDnsController < ApplicationController
  before_action :set_service
  before_action :set_zones

  def index
    @current_zone_id = params[:zone_id].presence || @service.default_zone_id
    @search = params[:search].to_s.strip
    @type_filter = params[:type].to_s.strip.upcase

    if @service.configured? && @current_zone_id.present?
      begin
        result = @service.list_dns_records(
          zone: @current_zone_id,
          type: @type_filter.presence,
          search: @search.presence
        )
        @records = result[:records]
    @records_info = result[:info]

        # Mapeamento e Correlação com Containers / Serviços Swarm e Regras Traefik
        map_dns_correlations
      rescue CloudflareService::Error => e
        @error = e.message
        @records = []
      end
    else
      @records = []
    end

    # Carrega Email Routing se a aba estiver ativa
    if params[:tab] == "email" && @service.configured?
      @email_routing = @service.email_routing_settings(zone: @current_zone_id)
      @email_rules = @service.list_email_routing_rules(zone: @current_zone_id)
      @destinations = @service.list_destination_addresses
    elsif params[:tab] == "turnstile" && @service.configured?
      @turnstile_widgets = @service.list_turnstile_widgets
    end

    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end

  def create
    zone_id = params[:zone_id].presence || @service.default_zone_id

    @service.create_dns_record(
      type: params[:type],
      name: params[:name],
      content: params[:content],
      ttl: params[:ttl].presence || 1,
      proxied: params[:proxied] == "1" || params[:proxied] == "true",
      priority: params[:priority],
      comment: params[:comment],
      zone: zone_id
    )

    redirect_to cloudflare_dns_path(zone_id: zone_id), notice: "Registro DNS '#{params[:name]}' criado com sucesso."
  rescue CloudflareService::Error => e
    redirect_to cloudflare_dns_path(zone_id: zone_id), alert: "Erro ao criar registro: #{e.message}"
  end

  def update
    zone_id = params[:zone_id].presence || @service.default_zone_id
    record_id = params[:id]

    @service.update_dns_record(
      record_id,
      type: params[:type],
      name: params[:name],
      content: params[:content],
      ttl: params[:ttl].presence || 1,
      proxied: params[:proxied] == "1" || params[:proxied] == "true",
      priority: params[:priority],
      comment: params[:comment],
      zone: zone_id
    )

    redirect_to cloudflare_dns_path(zone_id: zone_id), notice: "Registro DNS atualizado com sucesso."
  rescue CloudflareService::Error => e
    redirect_to cloudflare_dns_path(zone_id: zone_id), alert: "Erro ao atualizar registro: #{e.message}"
  end

  def destroy
    zone_id = params[:zone_id].presence || @service.default_zone_id
    record_id = params[:id]

    @service.delete_dns_record(record_id, zone: zone_id)
    redirect_to cloudflare_dns_path(zone_id: zone_id), notice: "Registro DNS removido com sucesso."
  rescue CloudflareService::Error => e
    redirect_to cloudflare_dns_path(zone_id: zone_id), alert: "Erro ao deletar registro: #{e.message}"
  end

  # ── Encaminhamento (Forwarding / CNAME Shortcut) ──
  def create_forward
    zone_id = params[:zone_id].presence || @service.default_zone_id
    source_subdomain = params[:source_subdomain].to_s.strip
    target_host = params[:target_host].to_s.strip
    proxied = params[:proxied] == "1" || params[:proxied] == "true"

    if source_subdomain.blank? || target_host.blank?
      return redirect_to cloudflare_dns_path(zone_id: zone_id), alert: "Origem e Destino do encaminhamento são obrigatórios."
    end

    @service.create_forward(
      source_name: source_subdomain,
      target_host: target_host,
      proxied: proxied,
      zone: zone_id
    )

    redirect_to cloudflare_dns_path(zone_id: zone_id), notice: "Encaminhamento '#{source_subdomain}' -> '#{target_host}' configurado com sucesso."
  rescue CloudflareService::Error => e
    redirect_to cloudflare_dns_path(zone_id: zone_id), alert: "Erro ao criar encaminhamento: #{e.message}"
  end

  # ── Email Routing Actions ──
  def create_email_rule
    zone_id = params[:zone_id].presence || @service.default_zone_id
    @service.create_email_routing_rule(
      name: params[:name].presence || "Regra #{params[:custom_address]}",
      custom_address: params[:custom_address],
      forward_to: params[:forward_to],
      enabled: params[:enabled] == "1" || params[:enabled] == "true",
      zone: zone_id
    )
    redirect_to cloudflare_dns_path(zone_id: zone_id, tab: "email"), notice: "Regra de email criada com sucesso."
  rescue CloudflareService::Error => e
    redirect_to cloudflare_dns_path(zone_id: zone_id, tab: "email"), alert: "Erro ao criar regra de email: #{e.message}"
  end

  def update_email_rule
    zone_id = params[:zone_id].presence || @service.default_zone_id
    rule_id = params[:id]
    @service.update_email_routing_rule(
      rule_id,
      name: params[:name].presence || "Regra #{params[:custom_address]}",
      custom_address: params[:custom_address],
      forward_to: params[:forward_to],
      enabled: params[:enabled] == "1" || params[:enabled] == "true",
      zone: zone_id
    )
    redirect_to cloudflare_dns_path(zone_id: zone_id, tab: "email"), notice: "Regra de email atualizada com sucesso."
  rescue CloudflareService::Error => e
    redirect_to cloudflare_dns_path(zone_id: zone_id, tab: "email"), alert: "Erro ao atualizar regra de email: #{e.message}"
  end

  def destroy_email_rule
    zone_id = params[:zone_id].presence || @service.default_zone_id
    rule_id = params[:id]
    @service.delete_email_routing_rule(rule_id, zone: zone_id)
    redirect_to cloudflare_dns_path(zone_id: zone_id, tab: "email"), notice: "Regra de email removida com sucesso."
  rescue CloudflareService::Error => e
    redirect_to cloudflare_dns_path(zone_id: zone_id, tab: "email"), alert: "Erro ao remover regra de email: #{e.message}"
  end

  # ── Turnstile Actions ──
  def create_turnstile
    zone_id = params[:zone_id].presence || @service.default_zone_id
    @service.create_turnstile_widget(
      name: params[:name],
      domains: params[:domains],
      mode: params[:mode].presence || "managed",
      bot_fight_mode: params[:bot_fight_mode] == "1" || params[:bot_fight_mode] == "true"
    )
    redirect_to cloudflare_dns_path(zone_id: zone_id, tab: "turnstile"), notice: "Widget Turnstile criado com sucesso."
  rescue CloudflareService::Error => e
    redirect_to cloudflare_dns_path(zone_id: zone_id, tab: "turnstile"), alert: "Erro ao criar Turnstile: #{e.message}"
  end

  def update_turnstile
    zone_id = params[:zone_id].presence || @service.default_zone_id
    widget_id = params[:id]
    @service.update_turnstile_widget(
      widget_id,
      name: params[:name],
      domains: params[:domains],
      mode: params[:mode].presence || "managed",
      bot_fight_mode: params[:bot_fight_mode] == "1" || params[:bot_fight_mode] == "true"
    )
    redirect_to cloudflare_dns_path(zone_id: zone_id, tab: "turnstile"), notice: "Widget Turnstile atualizado com sucesso."
  rescue CloudflareService::Error => e
    redirect_to cloudflare_dns_path(zone_id: zone_id, tab: "turnstile"), alert: "Erro ao atualizar Turnstile: #{e.message}"
  end

  def rotate_turnstile_secret
    zone_id = params[:zone_id].presence || @service.default_zone_id
    widget_id = params[:id]
    @service.rotate_turnstile_secret(widget_id, invalidate_immediately: params[:invalidate_immediately] == "1")
    redirect_to cloudflare_dns_path(zone_id: zone_id, tab: "turnstile"), notice: "Secret Key do Turnstile rotacionada com sucesso."
  rescue CloudflareService::Error => e
    redirect_to cloudflare_dns_path(zone_id: zone_id, tab: "turnstile"), alert: "Erro ao rotacionar secret: #{e.message}"
  end

  def destroy_turnstile
    zone_id = params[:zone_id].presence || @service.default_zone_id
    widget_id = params[:id]
    @service.delete_turnstile_widget(widget_id)
    redirect_to cloudflare_dns_path(zone_id: zone_id, tab: "turnstile"), notice: "Widget Turnstile removido com sucesso."
  rescue CloudflareService::Error => e
    redirect_to cloudflare_dns_path(zone_id: zone_id, tab: "turnstile"), alert: "Erro ao remover Turnstile: #{e.message}"
  end

  private

  def map_dns_correlations
    @correlated_targets = {}
    docker = DockerClient.new

    # Coleta regras de Host em serviços Swarm (Traefik labels)
    begin
      services = docker.services
      services.each do |svc|
        svc_name = svc.dig("Spec", "Name")
        labels = (svc.dig("Spec", "Labels") || {}).merge(svc.dig("Spec", "TaskTemplate", "ContainerSpec", "Labels") || {})
        labels.each do |k, v|
          if k.include?("traefik.http.routers") && k.include?(".rule") || k.include?("traefik.tcp.routers")
            hosts = v.scan(/Host\(`([^`]+)`\)/).flatten
            hosts.each do |h|
              @correlated_targets[h.downcase] ||= []
              @correlated_targets[h.downcase] << { type: :swarm_service, name: svc_name }
            end
          end
        end
      end
    rescue StandardError => e
      Rails.logger.warn("Erro ao ler serviços Swarm para correlação DNS: #{e.message}")
    end

    # Coleta regras em Containers individuais
    begin
      containers = docker.containers(all: true)
      containers.each do |c|
        c_name = (c["Names"] || []).first.to_s.sub(%r{^/}, "")
        c_labels = c["Labels"] || {}
        c_labels.each do |k, v|
          if k.include?("traefik.http.routers") && k.include?(".rule") || k.include?("traefik.tcp.routers")
            hosts = v.scan(/Host\(`([^`]+)`\)/).flatten
            hosts.each do |h|
              @correlated_targets[h.downcase] ||= []
              @correlated_targets[h.downcase] << { type: :container, name: c_name }
            end
          end
        end
      end
    rescue StandardError => e
      Rails.logger.warn("Erro ao ler containers para correlação DNS: #{e.message}")
    end

    # Correlaciona cada record com seu status de uso e target
    @records.each do |record|
      record_name = record["name"].to_s.downcase.strip
      record_content = record["content"].to_s.downcase.strip

      matches = @correlated_targets[record_name] || []
      # Se for apex ou www apontando pro swarm
      if matches.empty? && (record_name == "redhusky.com.br" || record_name == "www.redhusky.com.br")
        matches = [{ type: :swarm_service, name: "huskyos-prod_web" }]
      end

      record["in_use"] = matches.any?
      record["matched_containers"] = matches.uniq { |m| m[:name] }
    end
  end

  def set_service
    @service = CloudflareService.new
  end

  def set_zones
    @zones = @service.configured? ? @service.list_zones : []
  rescue CloudflareService::Error
    @zones = []
  end
end

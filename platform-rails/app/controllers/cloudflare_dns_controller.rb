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
      rescue CloudflareService::Error => e
        @error = e.message
        @records = []
      end
    else
      @records = []
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

  private

  def set_service
    @service = CloudflareService.new
  end

  def set_zones
    @zones = @service.configured? ? @service.list_zones : []
  rescue CloudflareService::Error
    @zones = []
  end
end

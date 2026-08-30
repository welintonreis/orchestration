# frozen_string_literal: true

require "net/http"
require "json"

class CloudflareService
  API_BASE = "https://api.cloudflare.com/client/v4"

  class Error < StandardError
    attr_reader :code, :payload

    def initialize(message, code: nil, payload: nil)
      super(message)
      @code = code
      @payload = payload
    end
  end

  def initialize(token: nil, zone_id: nil)
    @token = token.presence || ENV["CLOUDFLARE_DNS_API_TOKEN"].presence || ENV["CF_DNS_API_TOKEN"].presence
    @zone_id = zone_id.presence || ENV["CLOUDFLARE_ZONE_ID"].presence
  end

  def configured?
    @token.present?
  end

  # ── ZONES ──
  def list_zones
    res = request(:get, "/zones?per_page=50")
    res["result"] || []
  end

  def default_zone_id
    return @zone_id if @zone_id.present?

    first_zone = list_zones.first
    first_zone ? first_zone["id"] : nil
  rescue StandardError
    nil
  end

  # ── DNS RECORDS (CRUD) ──
  def list_dns_records(zone: nil, type: nil, name: nil, search: nil, page: 1, per_page: 100)
    target_zone = zone || default_zone_id
    raise Error.new("Zone ID não encontrada ou configurada") if target_zone.blank?

    params = { per_page: per_page, page: page }
    params[:type] = type if type.present?
    params[:name] = name if name.present?
    params[:search] = search if search.present?

    query = URI.encode_www_form(params)
    res = request(:get, "/zones/#{target_zone}/dns_records?#{query}")
    {
      records: res["result"] || [],
      info: res["result_info"] || {}
    }
  end

  def get_dns_record(record_id, zone: nil)
    target_zone = zone || default_zone_id
    res = request(:get, "/zones/#{target_zone}/dns_records/#{record_id}")
    res["result"]
  end

  def create_dns_record(type:, name:, content:, ttl: 1, proxied: false, priority: nil, comment: nil, zone: nil)
    target_zone = zone || default_zone_id
    payload = {
      type: type.to_s.upcase,
      name: name,
      content: content,
      ttl: ttl.to_i,
      proxied: proxied == true || proxied == "true" || proxied == "1"
    }
    payload[:priority] = priority.to_i if priority.present? && %w[MX SRV URI].include?(payload[:type])
    payload[:comment] = comment if comment.present?

    res = request(:post, "/zones/#{target_zone}/dns_records", payload)
    res["result"]
  end

  def update_dns_record(record_id, type:, name:, content:, ttl: 1, proxied: false, priority: nil, comment: nil, zone: nil)
    target_zone = zone || default_zone_id
    payload = {
      type: type.to_s.upcase,
      name: name,
      content: content,
      ttl: ttl.to_i,
      proxied: proxied == true || proxied == "true" || proxied == "1"
    }
    payload[:priority] = priority.to_i if priority.present? && %w[MX SRV URI].include?(payload[:type])
    payload[:comment] = comment if comment.present?

    res = request(:put, "/zones/#{target_zone}/dns_records/#{record_id}", payload)
    res["result"]
  end

  def delete_dns_record(record_id, zone: nil)
    target_zone = zone || default_zone_id
    request(:delete, "/zones/#{target_zone}/dns_records/#{record_id}")
    true
  end

  # ── ENCAMINHAMENTOS (CNAME / REDIRECIONAMENTOS DNS) ──
  # Cria atalho seguro de CNAME com proxy ativado ou apontamento A
  def create_forward(source_name:, target_host:, proxied: false, zone: nil)
    create_dns_record(
      type: "CNAME",
      name: source_name,
      content: target_host,
      ttl: 1,
      proxied: proxied,
      comment: "Encaminhamento configurado via Orchestration",
      zone: zone
    )
  end

  # ── EMAIL ROUTING (REGRAS DE EMAIL / ENCAMINHAMENTO) ──
  def email_routing_settings(zone: nil)
    target_zone = zone || default_zone_id
    res = request(:get, "/zones/#{target_zone}/email/routing")
    res["result"] || {}
  rescue Error => e
    { "status" => "disabled", "error" => e.message }
  end

  def list_email_routing_rules(zone: nil, page: 1, per_page: 50)
    target_zone = zone || default_zone_id
    res = request(:get, "/zones/#{target_zone}/email/routing/rules?page=#{page}&per_page=#{per_page}")
    res["result"] || []
  rescue Error => e
    Rails.logger.warn("Cloudflare Email Routing rules error: #{e.message}")
    []
  end

  def list_destination_addresses(account_id: nil)
    # Lista endereços de destino verificados na conta
    acc_id = account_id.presence || ENV["CF_ACCOUNT_ID"].presence || "85c7ebc56fe4c6aca4939b68af878c04"
    res = request(:get, "/accounts/#{acc_id}/email/routing/addresses")
    res["result"] || []
  rescue Error => e
    Rails.logger.warn("Cloudflare destination addresses error: #{e.message}")
    []
  end

  def create_email_routing_rule(name:, custom_address:, forward_to:, enabled: true, zone: nil)
    target_zone = zone || default_zone_id
    payload = {
      name: name,
      enabled: enabled == true || enabled == "true" || enabled == "1",
      matchers: [
        {
          type: "literal",
          field: "to",
          value: custom_address
        }
      ],
      actions: [
        {
          type: "forward",
          value: [forward_to]
        }
      ],
      priority: 0
    }
    res = request(:post, "/zones/#{target_zone}/email/routing/rules", payload)
    res["result"]
  end

  def update_email_routing_rule(rule_id, name:, custom_address:, forward_to:, enabled: true, zone: nil)
    target_zone = zone || default_zone_id
    payload = {
      name: name,
      enabled: enabled == true || enabled == "true" || enabled == "1",
      matchers: [
        {
          type: "literal",
          field: "to",
          value: custom_address
        }
      ],
      actions: [
        {
          type: "forward",
          value: [forward_to]
        }
      ],
      priority: 0
    }
    res = request(:put, "/zones/#{target_zone}/email/routing/rules/#{rule_id}", payload)
    res["result"]
  end

  def delete_email_routing_rule(rule_id, zone: nil)
    target_zone = zone || default_zone_id
    request(:delete, "/zones/#{target_zone}/email/routing/rules/#{rule_id}")
    true
  end

  # ── TURNSTILE (SMART CAPTCHA / WIDGETS) ──
  def list_turnstile_widgets(account_id: nil)
    acc_id = account_id.presence || ENV["CF_ACCOUNT_ID"].presence || "85c7ebc56fe4c6aca4939b68af878c04"
    res = request(:get, "/accounts/#{acc_id}/challenges/widgets")
    res["result"] || []
  rescue Error => e
    Rails.logger.warn("Cloudflare Turnstile list error: #{e.message}")
    []
  end

  def create_turnstile_widget(name:, domains:, mode: "managed", bot_fight_mode: false, account_id: nil)
    acc_id = account_id.presence || ENV["CF_ACCOUNT_ID"].presence || "85c7ebc56fe4c6aca4939b68af878c04"
    domains_list = domains.is_a?(Array) ? domains : domains.to_s.split(/[,\s\n]+/).map(&:strip).reject(&:blank?)
    payload = {
      name: name,
      domains: domains_list,
      mode: mode.presence || "managed",
      bot_fight_mode: bot_fight_mode == true || bot_fight_mode == "true" || bot_fight_mode == "1"
    }
    res = request(:post, "/accounts/#{acc_id}/challenges/widgets", payload)
    res["result"]
  end

  def update_turnstile_widget(widget_id, name:, domains:, mode: "managed", bot_fight_mode: false, account_id: nil)
    acc_id = account_id.presence || ENV["CF_ACCOUNT_ID"].presence || "85c7ebc56fe4c6aca4939b68af878c04"
    domains_list = domains.is_a?(Array) ? domains : domains.to_s.split(/[,\s\n]+/).map(&:strip).reject(&:blank?)
    payload = {
      name: name,
      domains: domains_list,
      mode: mode.presence || "managed",
      bot_fight_mode: bot_fight_mode == true || bot_fight_mode == "true" || bot_fight_mode == "1"
    }
    res = request(:put, "/accounts/#{acc_id}/challenges/widgets/#{widget_id}", payload)
    res["result"]
  end

  def rotate_turnstile_secret(widget_id, invalidate_immediately: false, account_id: nil)
    acc_id = account_id.presence || ENV["CF_ACCOUNT_ID"].presence || "85c7ebc56fe4c6aca4939b68af878c04"
    payload = {
      invalidate_immediately: invalidate_immediately == true || invalidate_immediately == "true"
    }
    res = request(:post, "/accounts/#{acc_id}/challenges/widgets/#{widget_id}/rotate_secret", payload)
    res["result"]
  end

  def delete_turnstile_widget(widget_id, account_id: nil)
    acc_id = account_id.presence || ENV["CF_ACCOUNT_ID"].presence || "85c7ebc56fe4c6aca4939b68af878c04"
    request(:delete, "/accounts/#{acc_id}/challenges/widgets/#{widget_id}")
    true
  end

  private

  def request(method, path, body = nil)
    raise Error.new("Cloudflare API Token não configurado no Orchestration") if @token.blank?

    uri = URI("#{API_BASE}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 15
    http.open_timeout = 5
    # Forçar IPv4 para evitar bloqueio Cloudflare API v4 em IPv6 dinâmico
    http.ipaddr = IPSocket.getaddress(uri.host) if defined?(IPSocket)

    klass = case method
            when :get then Net::HTTP::Get
            when :post then Net::HTTP::Post
            when :put then Net::HTTP::Put
            when :patch then Net::HTTP::Patch
            when :delete then Net::HTTP::Delete
            else raise ArgumentError, "Método HTTP não suportado: #{method}"
            end

    req = klass.new(uri.request_uri)
    req["Authorization"] = "Bearer #{@token}"
    req["Content-Type"] = "application/json"
    req.body = body.to_json if body.present?

    response = http.request(req)
    json = begin
      JSON.parse(response.body)
    rescue StandardError
      {}
    end

    if response.code.to_i >= 300 || json["success"] == false
      err_msg = json.dig("errors", 0, "message") || "Erro HTTP #{response.code}"
      raise Error.new(err_msg, code: response.code.to_i, payload: json)
    end

    json
  end
end

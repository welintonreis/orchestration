module AiQuota
  module Fetch
    # Anthropic reports utilization as a percentage, so `total` is literally 100
    # and `used` is the percentage consumed.
    class Claude < Base
      URL = "https://api.anthropic.com/api/oauth/usage".freeze
      BETA = "oauth-2025-04-20".freeze

      # Anthropic rate-limits this endpoint hard: cache per account and back off
      # after a 429, or the auto-refresh starts costing more than it reports.
      CACHE_TTL = 5.minutes
      RATE_LIMIT_COOLDOWN = 3.minutes

      # The named buckets carry internal codenames that mean nothing to a user
      # (tangelo, nimbus_quill, juniper_tide...). The `limits` array is the
      # curated view Anthropic itself renders, so prefer it and only fall back
      # to the buckets on an older response shape.
      BUCKETS = {
        "five_hour" => "Sessão (5h)",
        "seven_day" => "Semanal (7d)",
        "seven_day_opus" => "Semanal Opus (7d)",
        "seven_day_sonnet" => "Semanal Sonnet (7d)"
      }.freeze

      KIND_LABELS = {
        "session" => "Sessão (5h)",
        "weekly_all" => "Semanal (7d)",
        "weekly_opus" => "Semanal Opus (7d)",
        "weekly_sonnet" => "Semanal Sonnet (7d)"
      }.freeze

      def call
        token = account.credential&.dig("claudeAiOauth", "accessToken")
        return Result.error("Credencial não encontrada") if token.blank?

        status, body = get_json(URL, "Authorization" => "Bearer #{token}", "anthropic-beta" => BETA)

        return Result.error("Limite de consultas atingido — nova tentativa em instantes") if status == 429
        return Result.error("Credencial expirada — reautentique o CLI") if auth_error?(status, body)
        return Result.error("Anthropic respondeu #{status}") unless status == 200

        Result.new(plan: plan_of(body), quotas: quotas_from(body), extra: extra_from(body))
      end

      private

      def quotas_from(body)
        limits = body["limits"]
        limits.present? ? from_limits(limits) : from_buckets(body)
      end

      def from_limits(limits)
        limits.map do |l|
          pct = l["percent"].to_f
          Quota.new(
            name: KIND_LABELS.fetch(l["kind"], l["kind"].to_s.humanize),
            model_key: l["kind"],
            used: pct.round, total: 100,
            remaining_pct: Quota.remaining_from(remaining: 100 - pct),
            reset_at: parse_time(l["resets_at"]),
            recurring: true,
            severity: l["severity"]
          )
        end
      end

      def from_buckets(body)
        BUCKETS.filter_map do |key, label|
          bucket = body[key]
          next unless bucket.is_a?(Hash)

          util = bucket["utilization"].to_f
          Quota.new(
            name: label, model_key: key,
            used: util.round, total: 100,
            remaining_pct: Quota.remaining_from(remaining: 100 - util),
            reset_at: parse_time(bucket["resets_at"]),
            recurring: true,
            locked_reason: bucket["locked_reason"]
          )
        end
      end

      # Beyond the bars: the credit balance that covers you past the plan limit,
      # and the subscription tier — both worth showing on the card.
      def extra_from(body)
        spend = body["spend"] || {}
        return {} if spend.blank?

        {
          credits_used: money(spend["used"]),
          credits_limit: money(spend["limit"]),
          credits_pct: spend["percent"],
          credits_enabled: spend["enabled"],
          credits_disabled_reason: spend["disabled_reason"],
          currency: spend.dig("used", "currency")
        }.compact
      end

      def money(amount)
        return nil unless amount.is_a?(Hash) && amount["amount_minor"]

        amount["amount_minor"].to_f / (10**amount.fetch("exponent", 2).to_i)
      end

      def plan_of(_body)
        account.credential&.dig("claudeAiOauth", "subscriptionType")&.titleize
      end

      def parse_time(value)
        Time.zone.parse(value.to_s) if value.present?
      end
    end
  end
end

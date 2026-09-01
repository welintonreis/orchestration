module AiQuota
  module Fetch
    # ChatGPT/Codex reports percentages, so total is 100 like claude.
    #
    # Shape verified against the live endpoint on 2026-09-01: the windows live
    # under `rate_limit`, `reset_at` is epoch seconds (not an ISO string), and
    # each window carries `limit_window_seconds` — so the label is derived from
    # the window length rather than assumed. A plan whose window is 30 days
    # would otherwise be mislabelled "5h".
    class Codex < Base
      URL = "https://chatgpt.com/backend-api/wham/usage".freeze
      CACHE_TTL = 1.minute

      # Each family reports the same pair of windows.
      FAMILIES = {
        "rate_limit" => "",
        "code_review_rate_limit" => "Review ",
        "spark_rate_limit" => "Spark "
      }.freeze

      WINDOWS = %w[primary_window secondary_window].freeze

      # Common window lengths, so the usual cases read the way the provider's
      # own UI phrases them.
      WINDOW_LABELS = {
        18_000 => "Sessão (5h)",
        604_800 => "Semanal (7d)",
        2_592_000 => "Mensal (30d)"
      }.freeze

      def call
        token = account.credential&.dig("tokens", "access_token")
        return Result.error("Credencial não encontrada") if token.blank?

        status, body = get_json(URL, "Authorization" => "Bearer #{token}")

        return Result.error("Credencial expirada — renove o token") if auth_error?(status, body)
        return Result.error("ChatGPT respondeu #{status}") unless status == 200

        adopt_identity(body)
        Result.new(plan: body["plan_type"]&.titleize, quotas: quotas_from(body), extra: extra_from(body))
      end

      private

      def quotas_from(body)
        FAMILIES.flat_map do |family_key, prefix|
          family = body[family_key]
          next [] unless family.is_a?(Hash)

          WINDOWS.filter_map { |window_key| quota_for(family[window_key], prefix, family_key, window_key) }
        end
      end

      def quota_for(window, prefix, family_key, window_key)
        return nil unless window.is_a?(Hash)

        used = window["used_percent"].to_f.clamp(0, 100).round
        Quota.new(
          name: "#{prefix}#{window_label(window, window_key)}".strip,
          model_key: "#{family_key}.#{window_key}",
          used: used, total: 100,
          remaining_pct: Quota.remaining_from(remaining: 100 - used),
          reset_at: reset_of(window),
          recurring: true
        )
      end

      def window_label(window, window_key)
        seconds = window["limit_window_seconds"].to_i
        return WINDOW_LABELS[seconds] if WINDOW_LABELS.key?(seconds)
        return humanized_window(seconds) if seconds.positive?

        window_key == "primary_window" ? "Primária" : "Secundária"
      end

      def humanized_window(seconds)
        return "Janela (#{seconds / 86_400}d)" if seconds >= 86_400
        return "Janela (#{seconds / 3_600}h)" if seconds >= 3_600

        "Janela (#{seconds / 60}min)"
      end

      # Epoch seconds when present, else a relative countdown.
      def reset_of(window)
        return Time.zone.at(window["reset_at"].to_i) if window["reset_at"].to_i.positive?

        seconds = window["reset_after_seconds"]
        Time.current + seconds.to_i.seconds if seconds.present?
      end

      # The endpoint knows the account's email; a card labelled by an opaque
      # account_id is worse than one labelled by who it belongs to.
      def adopt_identity(body)
        return unless account.persisted?
        return if body["email"].blank? || account.email == body["email"]

        account.update_columns(email: body["email"], display_name: body["plan_type"])
      end

      # Beyond the bars: reset credits skip a cooldown, and the credit balance
      # is what covers you once the window is exhausted — both are acted on.
      def extra_from(body)
        credits = body["credits"] || {}
        {
          limit_reached: body.dig("rate_limit", "limit_reached"),
          reset_credits: body.dig("rate_limit_reset_credits", "available_count"),
          credits_balance: credits["balance"],
          credits_unlimited: credits["unlimited"],
          approx_messages: credits["approx_local_messages"]
        }.compact
      end
    end
  end
end

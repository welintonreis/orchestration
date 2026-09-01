module AiQuota
  module Refresh
    class Codex < Base
      URL = "https://auth.openai.com/oauth/token".freeze
      # Public client id of the Codex CLI — it ships inside the CLI, not a secret.
      CLIENT_ID = "app_EMoamEEZ73f0CkXaXp7hrann".freeze

      private

      def renew
        token = account.credential&.dig("tokens", "refresh_token")
        return nil if token.blank?

        status, body = post_json(URL, {
          client_id: CLIENT_ID,
          grant_type: "refresh_token",
          refresh_token: token,
          scope: "openid profile email"
        })

        status == 200 && body["access_token"].present? ? body : nil
      end

      def merge_into(credential, payload)
        previous = credential["tokens"] || {}
        tokens = previous.merge(
          "access_token"  => payload["access_token"],
          # Keep the old one only if the provider didn't rotate it.
          "refresh_token" => payload["refresh_token"].presence || previous["refresh_token"]
        )
        tokens["id_token"] = payload["id_token"] if payload["id_token"].present?

        credential.merge("tokens" => tokens, "last_refresh" => Time.current.utc.iso8601)
      end
    end
  end
end

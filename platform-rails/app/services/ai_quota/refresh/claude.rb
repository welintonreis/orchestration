module AiQuota
  module Refresh
    class Claude < Base
      URL = "https://console.anthropic.com/v1/oauth/token".freeze
      # Public client id of the Claude Code CLI.
      CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e".freeze

      private

      def renew
        token = account.credential&.dig("claudeAiOauth", "refreshToken")
        return nil if token.blank?

        status, body = post_json(URL, {
          client_id: CLIENT_ID,
          grant_type: "refresh_token",
          refresh_token: token
        })

        status == 200 && body["access_token"].present? ? body : nil
      end

      def merge_into(credential, payload)
        previous = credential["claudeAiOauth"] || {}
        oauth = previous.merge(
          "accessToken"  => payload["access_token"],
          "refreshToken" => payload["refresh_token"].presence || previous["refreshToken"],
          # The CLI stores expiry as epoch milliseconds, not seconds-from-now.
          "expiresAt"    => (Time.current + payload["expires_in"].to_i.seconds).to_i * 1000
        )

        credential.merge("claudeAiOauth" => oauth)
      end
    end
  end
end

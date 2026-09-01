require "net/http"
require "json"
require "securerandom"
require "digest"
require "base64"

module AiQuota
  # Independent Claude accounts, each with its own OAuth login — as opposed to
  # ImportLocal, which only ever sees the one account the host's Claude Code
  # CLI happens to be logged into. Flat module, not a Base-class hierarchy
  # like Fetch/Refresh: those exist because 2+ providers needed the shared
  # shape, this is Claude-only until a second provider actually asks for it.
  #
  # Reuses Refresh::Claude's URL/CLIENT_ID — same OAuth app, just the
  # authorization_code leg instead of refresh_token.
  module ConnectClaude
    module_function

    AUTHORIZE_URL = "https://claude.ai/oauth/authorize".freeze
    REDIRECT_URI  = "https://console.anthropic.com/oauth/code/callback".freeze
    SCOPE         = "org:create_api_key user:profile user:inference".freeze

    # PKCE verifier: 32 random bytes, base64url, no padding.
    def new_verifier
      Base64.urlsafe_encode64(SecureRandom.random_bytes(32), padding: false)
    end

    # state is deliberately the verifier itself, not a separate random value —
    # that's what Anthropic's own CLI does, not a shortcut we're taking.
    def authorize_url(verifier)
      challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
      params = {
        code: true, response_type: "code", client_id: Refresh::Claude::CLIENT_ID,
        redirect_uri: REDIRECT_URI, scope: SCOPE,
        code_challenge: challenge, code_challenge_method: "S256", state: verifier
      }
      "#{AUTHORIZE_URL}?#{URI.encode_www_form(params)}"
    end

    # pasted is the "code#state" string Anthropic's callback page displays for
    # manual copy-paste (that redirect_uri isn't ours to intercept). Returns
    # the {"claudeAiOauth" => {...}} hash on success, nil otherwise — same
    # shape ImportLocal/Refresh::Claude already read, so nothing downstream
    # needs to know this credential didn't come from the CLI's file.
    def exchange!(pasted, verifier)
      code, state = pasted.to_s.split("#", 2)
      return nil if code.blank? || state != verifier

      status, body = post_json(Refresh::Claude::URL, {
        code: code, state: state, grant_type: "authorization_code",
        client_id: Refresh::Claude::CLIENT_ID, redirect_uri: REDIRECT_URI, code_verifier: verifier
      })
      return nil unless status == 200 && body["access_token"].present?

      {
        "claudeAiOauth" => {
          "accessToken"  => body["access_token"],
          "refreshToken" => body["refresh_token"],
          "expiresAt"    => (Time.current + body["expires_in"].to_i.seconds).to_i * 1000,
          "scopes"       => body["scope"].to_s.split(" "),
          "subscriptionType" => body.dig("account", "subscription_type")
        }
      }
    end

    def create_account!(credential)
      AiAccount.create!(provider: "claude", credential_source: "inline", credential: credential)
    end

    def post_json(url, body)
      uri = URI(url)
      req = Net::HTTP::Post.new(uri)
      req["Accept"] = "application/json"
      req["Content-Type"] = "application/json"
      req.body = body.to_json

      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 10) { |http| http.request(req) }
      [ res.code.to_i, JSON.parse(res.body.to_s) ]
    rescue StandardError => e
      [ 0, { "error" => { "message" => e.message } } ]
    end
  end
end

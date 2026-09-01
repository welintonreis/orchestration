require "test_helper"

module AiQuota
  # Contas independentes, não a briga de refresh-token que ImportLocal evita
  # (ver docs/specs/feature-ai-quota.md, fase A6): cada login aqui é uma conta
  # Claude diferente, sem arquivo nenhum disputando o mesmo refresh token.
  class ConnectClaudeTest < ActiveSupport::TestCase
    test "authorize_url's code_challenge is the SHA-256 of the verifier, base64url" do
      verifier = ConnectClaude.new_verifier
      url = ConnectClaude.authorize_url(verifier)

      params = Rack::Utils.parse_query(URI(url).query)
      assert_equal verifier, params["state"], "state deve ser o proprio verifier, igual ao CLI oficial"
      assert_equal "S256", params["code_challenge_method"]
      assert_equal Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false), params["code_challenge"]
    end

    test "a successful exchange creates an inline account in the CLI's own credential shape" do
      verifier = ConnectClaude.new_verifier
      credential = stub_post(200, { "access_token" => "acc", "refresh_token" => "ref", "expires_in" => 3600 }) do
        ConnectClaude.exchange!("codigo123##{verifier}", verifier)
      end

      assert_equal "acc", credential.dig("claudeAiOauth", "accessToken")
      assert_equal "ref", credential.dig("claudeAiOauth", "refreshToken")
      assert credential.dig("claudeAiOauth", "expiresAt") > 1_000_000_000_000, "deveria ser epoch em ms"
    end

    test "two logins create two independent accounts, not one fighting over a shared refresh token" do
      verifier1 = ConnectClaude.new_verifier
      credential1 = stub_post(200, { "access_token" => "a1", "refresh_token" => "r1", "expires_in" => 3600 }) do
        ConnectClaude.exchange!("c1##{verifier1}", verifier1)
      end
      account1 = ConnectClaude.create_account!(credential1)

      verifier2 = ConnectClaude.new_verifier
      credential2 = stub_post(200, { "access_token" => "a2", "refresh_token" => "r2", "expires_in" => 3600 }) do
        ConnectClaude.exchange!("c2##{verifier2}", verifier2)
      end
      account2 = ConnectClaude.create_account!(credential2)

      assert_not_equal account1.id, account2.id
      assert_equal "r1", account1.reload.credential.dig("claudeAiOauth", "refreshToken")
      assert_equal "r2", account2.reload.credential.dig("claudeAiOauth", "refreshToken")
    end

    test "a state that doesn't match the verifier is rejected without calling the network" do
      verifier = ConnectClaude.new_verifier
      called = false
      original = ConnectClaude.method(:post_json)
      ConnectClaude.define_singleton_method(:post_json) { |*| called = true; [ 200, {} ] }
      result = ConnectClaude.exchange!("codigo#outro-state", verifier)
      ConnectClaude.define_singleton_method(:post_json, original)

      assert_nil result
      assert_not called, "nao deveria nem tentar trocar o token com state errado"
    end

    test "a paste with no '#' is rejected" do
      verifier = ConnectClaude.new_verifier
      assert_nil ConnectClaude.exchange!("so-codigo-sem-hash", verifier)
    end

    test "a code Anthropic rejects returns nil, no account created" do
      verifier = ConnectClaude.new_verifier
      result = stub_post(400, { "error" => "invalid_grant" }) do
        ConnectClaude.exchange!("codigo-invalido##{verifier}", verifier)
      end

      assert_nil result
    end

    private

    def stub_post(status, body)
      original = ConnectClaude.method(:post_json)
      ConnectClaude.define_singleton_method(:post_json) { |*| [ status, body ] }
      yield
    ensure
      ConnectClaude.define_singleton_method(:post_json, original)
    end
  end
end

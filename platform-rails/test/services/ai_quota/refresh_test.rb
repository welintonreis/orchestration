require "test_helper"

module AiQuota
  # The rotation behaviour here is not hypothetical: renewing the Codex token on
  # 2026-09-01 returned a new refresh token and left the CLI's file holding a
  # dead one. These tests exist so that can't happen silently again.
  class RefreshTest < ActiveSupport::TestCase
    setup do
      @dir = Dir.mktmpdir
      @path = File.join(@dir, "auth.json")
      File.write(@path, JSON.generate({
        "auth_mode" => "chatgpt",
        "tokens" => { "access_token" => "velho", "refresh_token" => "r-velho", "account_id" => "acc" }
      }))
    end

    teardown { FileUtils.remove_entry(@dir) }

    test "a rotated refresh token is written back to the CLI file, not kept to ourselves" do
      assert renew(file_account, { "access_token" => "novo", "refresh_token" => "r-novo" })

      written = JSON.parse(File.read(@path))
      assert_equal "novo", written.dig("tokens", "access_token")
      assert_equal "r-novo", written.dig("tokens", "refresh_token")
      # Untouched fields survive — we merge, never rewrite the file wholesale.
      assert_equal "acc", written.dig("tokens", "account_id")
      assert_equal "chatgpt", written["auth_mode"]
      assert written["last_refresh"].present?
    end

    test "a provider that does not rotate keeps the existing refresh token" do
      assert renew(file_account, { "access_token" => "novo" })

      assert_equal "r-velho", JSON.parse(File.read(@path)).dig("tokens", "refresh_token")
    end

    test "the credential file keeps owner-only permissions" do
      renew(file_account, { "access_token" => "novo", "refresh_token" => "r-novo" })

      assert_equal "600", format("%o", File.stat(@path).mode & 0o777)
    end

    test "a failed renewal leaves the file exactly as it was" do
      before = File.read(@path)
      assert_not renew(file_account, {}, status: 400)

      assert_equal before, File.read(@path)
      assert_empty Dir.glob(File.join(@dir, ".*.*")), "sobrou arquivo temporario"
    end

    test "an inline credential is saved to the record instead of a file" do
      account = AiAccount.create!(provider: "codex", credential_source: "inline")
      account.credential = { "tokens" => { "refresh_token" => "r-velho" } }
      account.save!

      assert renew(account, { "access_token" => "novo", "refresh_token" => "r-novo" })
      assert_equal "novo", account.reload.credential.dig("tokens", "access_token")
    end

    test "claude stores expiry as epoch milliseconds, the way its CLI reads it" do
      account = AiAccount.new(provider: "claude", credential_source: "inline")
      account.credential = { "claudeAiOauth" => { "refreshToken" => "r" } }

      renew(account, { "access_token" => "novo", "expires_in" => 3600 }, refresher: Refresh::Claude)

      expires_at = account.credential.dig("claudeAiOauth", "expiresAt")
      assert_in_delta 1.hour.from_now.to_i * 1000, expires_at, 5000
      assert expires_at > 1_000_000_000_000, "deveria ser epoch em ms, veio #{expires_at}"
    end

    private

    def file_account
      AiAccount.new(provider: "codex", credential_source: "file", credential_path: @path)
    end

    def renew(account, body, status: 200, refresher: Refresh::Codex)
      service = refresher.new(account)
      service.define_singleton_method(:post_json) { |*| [ status, body ] }
      service.call
    end
  end
end

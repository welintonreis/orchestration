require "test_helper"

module AiQuota
  class ImportLocalTest < ActiveSupport::TestCase
    test "identity_for handles claude, codex, and antigravity correctly" do
      Dir.mktmpdir do |dir|
        claude_file = File.join(dir, "claude.json")
        File.write(claude_file, { "claudeAiOauth" => { "subscriptionType" => "pro" } }.to_json)
        assert_equal "pro", ImportLocal.identity_for("claude", claude_file)

        codex_file = File.join(dir, "codex.json")
        File.write(codex_file, { "account_id" => "123" }.to_json)
        assert_nil ImportLocal.identity_for("codex", codex_file)

        agy_file = File.join(dir, "antigravity.json")
        File.write(agy_file, { "token" => { "access_token" => "xyz" } }.to_json)
        assert_equal "Antigravity CLI", ImportLocal.identity_for("antigravity", agy_file)
      end
    end
  end
end

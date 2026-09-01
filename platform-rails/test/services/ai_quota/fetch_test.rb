require "test_helper"

module AiQuota
  # Parser tests: no network. The payload shapes below mirror what the real
  # endpoints returned on 2026-09-01 (values changed, structure kept).
  class FetchTest < ActiveSupport::TestCase
    CLAUDE_BODY = {
      "five_hour" => { "utilization" => 58.0, "resets_at" => "2026-09-01T13:20:00Z", "locked_reason" => nil },
      "seven_day" => { "utilization" => 58.0, "resets_at" => "2026-09-06T08:00:00Z" },
      "nimbus_quill" => { "utilization" => 0.0, "resets_at" => nil },
      "limits" => [
        { "kind" => "session",     "percent" => 58, "severity" => "normal", "resets_at" => "2026-09-01T13:20:00Z" },
        { "kind" => "weekly_all",  "percent" => 12, "severity" => "normal", "resets_at" => "2026-09-06T08:00:00Z" }
      ],
      "spend" => {
        "used"  => { "amount_minor" => 250, "currency" => "USD", "exponent" => 2 },
        "limit" => { "amount_minor" => 5244, "currency" => "USD", "exponent" => 2 },
        "percent" => 5, "enabled" => false, "disabled_reason" => "out_of_credits"
      }
    }.freeze

    test "claude prefers the curated limits array over the codenamed buckets" do
      result = claude_result(CLAUDE_BODY)

      assert_equal [ "Sessão (5h)", "Semanal (7d)" ], result.quotas.map(&:name)
      # nimbus_quill and friends are internal codenames — they must not leak.
      assert_not_includes result.quotas.map(&:model_key), "nimbus_quill"
    end

    test "claude converts utilization into remaining, not used" do
      session = claude_result(CLAUDE_BODY).quotas.first

      assert_equal 58, session.used
      assert_equal 100, session.total
      assert_equal 42, session.remaining_pct
      assert_equal :yellow, session.color
    end

    test "claude falls back to the named buckets when limits is absent" do
      body = CLAUDE_BODY.except("limits")
      names = claude_result(body).quotas.map(&:name)

      assert_equal [ "Sessão (5h)", "Semanal (7d)" ], names
    end

    test "claude surfaces the credit balance alongside the bars" do
      extra = claude_result(CLAUDE_BODY).extra

      assert_in_delta 2.50, extra[:credits_used], 0.001
      assert_in_delta 52.44, extra[:credits_limit], 0.001
      assert_equal "out_of_credits", extra[:credits_disabled_reason]
    end

    test "claude reports an expired credential as a message, not as zero quota" do
      result = claude_result({ "error" => "token expired" }, status: 401)

      assert_not result.ok?
      assert_empty result.quotas
      assert_match(/expirada/i, result.message)
    end

    test "claude backs off instead of hammering a rate limit" do
      assert_match(/limite de consultas/i, claude_result({}, status: 429).message)
    end

    # Shape captured from the live endpoint on 2026-09-01: windows nest under
    # rate_limit, reset_at is epoch seconds, and the window length is data.
    CODEX_BODY = {
      "plan_type" => "free",
      "email" => "quem@exemplo.com",
      "rate_limit" => {
        "limit_reached" => true,
        "primary_window"   => { "used_percent" => 100, "limit_window_seconds" => 2_592_000, "reset_at" => 1_789_519_088 },
        "secondary_window" => nil
      },
      "code_review_rate_limit" => {
        "primary_window" => { "used_percent" => 40, "limit_window_seconds" => 18_000, "reset_after_seconds" => 3600 }
      },
      "credits" => { "unlimited" => false, "balance" => nil },
      "rate_limit_reset_credits" => { "available_count" => 2 }
    }.freeze

    test "codex names each window by its actual length, not by position" do
      result = codex_result(CODEX_BODY)

      # A 30-day window mislabelled "5h" is the bug this guards against.
      assert_equal [ "Mensal (30d)", "Review Sessão (5h)" ], result.quotas.map(&:name)
      assert_equal "Free", result.plan
    end

    test "codex falls back to a humanized label for an unknown window length" do
      body = { "rate_limit" => { "primary_window" => { "used_percent" => 10, "limit_window_seconds" => 7_200 } } }

      assert_equal "Janela (2h)", codex_result(body).quotas.first.name
    end

    test "codex reads reset_at as epoch seconds and reset_after as a countdown" do
      quotas = codex_result(CODEX_BODY).quotas

      assert_equal Time.zone.at(1_789_519_088), quotas.first.reset_at
      assert_in_delta 1.hour.from_now, quotas.second.reset_at, 5
    end

    test "codex skips a family the account does not have" do
      # secondary_window is nil here, and spark_rate_limit is absent entirely.
      assert_equal 2, codex_result(CODEX_BODY).quotas.size
    end

    test "codex flags the exhausted window and keeps reset credits" do
      result = codex_result(CODEX_BODY)

      assert result.quotas.first.empty?, "100% usado deveria contar como vazio"
      assert result.any_empty?
      assert_equal 2, result.extra[:reset_credits]
      assert result.extra[:limit_reached]
    end

    test "codex clamps a percentage the provider overshoots" do
      body = { "rate_limit" => { "primary_window" => { "used_percent" => 140, "limit_window_seconds" => 18_000 } } }

      assert_equal 100, codex_result(body).quotas.first.used
      assert_equal 0, codex_result(body).quotas.first.remaining_pct
    end

    test "lowest and next_reset drive the summary tiles" do
      result = codex_result(CODEX_BODY)

      assert_equal "Mensal (30d)", result.lowest.name
      assert_equal result.quotas.map(&:reset_at).compact.min, result.next_reset
    end

    private

    def claude_result(body, status: 200)
      account = AiAccount.new(provider: "claude", credential_source: "inline")
      account.credential = { "claudeAiOauth" => { "accessToken" => "t", "subscriptionType" => "pro" } }
      fetch_with(Fetch::Claude.new(account), status, body)
    end

    def codex_result(body, status: 200)
      account = AiAccount.new(provider: "codex", credential_source: "inline")
      account.credential = { "tokens" => { "access_token" => "t" } }
      fetch_with(Fetch::Codex.new(account), status, body)
    end

    # Swap the HTTP leg for a canned response — the parser is what's under test.
    def fetch_with(fetcher, status, body)
      fetcher.define_singleton_method(:get_json) { |*| [ status, body ] }
      fetcher.call
    end
  end
end

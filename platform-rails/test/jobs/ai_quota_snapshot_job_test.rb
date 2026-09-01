require "test_helper"

class AiQuotaSnapshotJobTest < ActiveJob::TestCase
  setup do
    @account = AiAccount.create!(provider: "claude", credential_source: "inline", name: "conta")
  end

  test "records one row per quota window" do
    with_usage(->(*) { result_with(40) }) { AiQuotaSnapshotJob.perform_now }

    assert_equal 1, AiQuotaSnapshot.count
    snapshot = AiQuotaSnapshot.first
    assert_equal "Sessão (5h)", snapshot.quota_name
    assert_equal 40, snapshot.remaining_pct
  end

  test "skips accounts whose fetch failed, so a trend never records a fake zero" do
    with_usage(->(*) { AiQuota::Result.error("expirada") }) { AiQuotaSnapshotJob.perform_now }

    assert_equal 0, AiQuotaSnapshot.count
  end

  test "one broken provider does not stop the others from being recorded" do
    other = AiAccount.create!(provider: "codex", credential_source: "inline", name: "ok")

    with_usage(->(account, **) { raise "boom" if account.id == @account.id; result_with(70) }) do
      AiQuotaSnapshotJob.perform_now
    end

    assert_equal [ other.id ], AiQuotaSnapshot.pluck(:ai_account_id)
  end

  test "inactive accounts are not polled" do
    @account.update!(active: false)
    with_usage(->(*) { raise "não deveria consultar conta desligada" }) { AiQuotaSnapshotJob.perform_now }

    assert_equal 0, AiQuotaSnapshot.count
  end

  test "purges readings past the retention window" do
    AiQuotaSnapshot.create!(ai_account: @account, quota_name: "velha", remaining_pct: 1,
                            captured_at: 91.days.ago, created_at: 91.days.ago)
    fresh = AiQuotaSnapshot.create!(ai_account: @account, quota_name: "nova", remaining_pct: 1,
                                    captured_at: 1.day.ago, created_at: 1.day.ago)

    with_usage(->(*) { AiQuota::Result.error("skip") }) { AiQuotaSnapshotJob.perform_now }

    assert_equal [ fresh.id ], AiQuotaSnapshot.pluck(:id)
  end

  private

  def result_with(remaining)
    AiQuota::Result.new(quotas: [
      AiQuota::Quota.new(name: "Sessão (5h)", model_key: "session", used: 100 - remaining,
                         total: 100, remaining_pct: remaining, reset_at: 1.hour.from_now)
    ], extra: {})
  end

  def with_usage(callable)
    original = AiQuota::Usage.method(:for)
    AiQuota::Usage.define_singleton_method(:for) { |account, **opts| callable.call(account, **opts) }
    yield
  ensure
    AiQuota::Usage.define_singleton_method(:for, original)
  end
end

require "test_helper"

class AiQuotaControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:admin_user)
    @account = AiAccount.create!(provider: "claude", credential_source: "inline", name: "conta-teste")
    @account.update!(credential: { "claudeAiOauth" => { "accessToken" => "t" } })
  end

  # Same contract as every other converted screen: the shell must not touch the
  # network, so a dead provider can't stall the page.
  test "GET index renders the shell without calling any provider" do
    stub_usage(->(*) { raise "não deveria consultar o provedor no shell" }) do
      get ai_quota_url
      assert_response :success
    end
    assert_select "turbo-frame#ai-account-#{@account.id}[src=?]", card_ai_quota_path(@account)
    assert_select "turbo-frame#ai-quota-summary[src=?]", summary_ai_quota_path
  end

  test "GET card renders the quota bars" do
    stub_usage(->(*) { ok_result }) do
      get card_ai_quota_url(@account)
      assert_response :success
    end
    assert_select "turbo-frame#ai-account-#{@account.id}"
    assert_match "Sessão (5h)", response.body
    assert_match "40%", response.body
  end

  # An expired credential must read as an error, never as "quota zerada" — the
  # two mean opposite things to whoever is looking at the screen.
  test "GET card shows a failed fetch as a message, not as empty bars" do
    stub_usage(->(*) { AiQuota::Result.error("Credencial expirada") }) do
      get card_ai_quota_url(@account)
      assert_response :success
    end
    assert_match "Credencial expirada", response.body
    assert_select "turbo-frame .h-2.rounded-full", false
  end

  test "GET summary aggregates the lowest quota and the next reset" do
    stub_usage(->(*) { ok_result }) do
      get summary_ai_quota_url
      assert_response :success
    end
    assert_match "Menor quota", response.body
    assert_match "40%", response.body
  end

  test "POST toggle flips the account and records an audit entry" do
    assert_difference -> { AuditLog.count } do
      post toggle_ai_quota_url(@account)
    end
    assert_not @account.reload.active?
    assert_equal "ai_account.disable", AuditLog.order(:created_at).last.action
  end

  test "bulk toggle only switches off the accounts that are actually empty" do
    full = AiAccount.create!(provider: "codex", credential_source: "inline", name: "cheia")

    stub_usage(->(account, **) { account.id == @account.id ? empty_result : ok_result }) do
      post bulk_toggle_ai_quota_url(to: "off")
    end

    assert_not @account.reload.active?, "conta vazia deveria ser desligada"
    assert full.reload.active?, "conta com quota nao deveria ser tocada"
  end

  test "DELETE removes the account" do
    assert_difference -> { AiAccount.count }, -1 do
      delete destroy_ai_quota_url(@account)
    end
  end

  private

  def ok_result
    AiQuota::Result.new(plan: "Pro", quotas: [
      AiQuota::Quota.new(name: "Sessão (5h)", used: 60, total: 100, remaining_pct: 40, reset_at: 2.hours.from_now)
    ], extra: {})
  end

  def empty_result
    AiQuota::Result.new(quotas: [
      AiQuota::Quota.new(name: "Sessão (5h)", used: 98, total: 100, remaining_pct: 2, reset_at: 1.hour.from_now)
    ], extra: {})
  end

  def stub_usage(callable)
    original = AiQuota::Usage.method(:for)
    AiQuota::Usage.define_singleton_method(:for) { |account, **opts| callable.call(account, **opts) }
    yield
  ensure
    AiQuota::Usage.define_singleton_method(:for, original)
  end
end

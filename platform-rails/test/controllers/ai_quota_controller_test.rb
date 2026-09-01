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

  test "GET new_claude_login stashes the verifier in session and shows the authorize link" do
    get new_claude_login_ai_quota_url
    assert_response :success
    assert session[:claude_oauth_verifier].present?
    assert_match "claude.ai/oauth/authorize", response.body
  end

  test "POST create_claude_login exchanges the code, creates the account and audits it" do
    get new_claude_login_ai_quota_url
    verifier = session[:claude_oauth_verifier]

    original = AiQuota::ConnectClaude.method(:post_json)
    AiQuota::ConnectClaude.define_singleton_method(:post_json) { |*| [ 200, { "access_token" => "a", "refresh_token" => "r", "expires_in" => 3600 } ] }
    begin
      assert_difference -> { AiAccount.count }, 1 do
        post create_claude_login_ai_quota_url, params: { code: "codigo##{verifier}" }
      end
    ensure
      AiQuota::ConnectClaude.define_singleton_method(:post_json, original)
    end

    assert_redirected_to ai_quota_path
    assert_equal "ai_account.connect", AuditLog.order(:created_at).last.action
    assert_nil session[:claude_oauth_verifier], "verifier de uso unico deve ser apagado apos o uso"
  end

  test "POST create_claude_login with a bad code creates no account" do
    get new_claude_login_ai_quota_url

    assert_no_difference -> { AiAccount.count } do
      post create_claude_login_ai_quota_url, params: { code: "codigo-sem-hash" }
    end
    assert_redirected_to new_claude_login_ai_quota_path
  end

  test "GET new_ollama_key renders form" do
    get new_ollama_key_ai_quota_url
    assert_response :success
    assert_match "Ollama", response.body
  end

  test "POST create_ollama_key creates an inline ollama account and audits it" do
    assert_difference -> { AiAccount.count }, 1 do
      post create_ollama_key_ai_quota_url, params: { name: "Ollama Servidor", api_key: "secret123" }
    end

    assert_redirected_to ai_quota_path
    assert_equal "ai_account.connect", AuditLog.order(:created_at).last.action
    account = AiAccount.order(:created_at).last
    assert_equal "ollama", account.provider
    assert_equal "inline", account.credential_source
    assert_equal "secret123", account.credential["apiKey"]
  end

  test "POST create_ollama_key with empty api_key redirects with alert" do
    assert_no_difference -> { AiAccount.count } do
      post create_ollama_key_ai_quota_url, params: { name: "Ollama", api_key: "" }
    end
    assert_redirected_to new_ollama_key_ai_quota_path
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

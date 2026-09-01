# frozen_string_literal: true

# Native AI quota screen. Was an iframe of 9router's dashboard; now the platform
# holds its own accounts and reads the providers directly — see
# docs/specs/feature-ai-quota.md for why that trade was made.
class AiQuotaController < ApplicationController
  before_action :set_account, only: %i[card toggle destroy refresh]

  # Shell only. Every card fetches its own quota through a lazy frame, so N slow
  # provider calls happen in parallel in the browser instead of in series here.
  def index
    @accounts = filtered_accounts
    @providers = AiAccount.distinct.pluck(:provider).sort
  end

  # Summary tiles: needs every account's quota, so it gets its own lazy frame
  # rather than holding up the cards.
  def summary
    @results = AiAccount.active.by_priority.to_h { |a| [ a, AiQuota::Usage.for(a) ] }
  end

  def card
    @result = AiQuota::Usage.for(@account, force: params[:force].present?)
    render layout: false
  end

  def toggle
    @account.update!(active: !@account.active)
    audit!(@account.active? ? "ai_account.enable" : "ai_account.disable")
    redirect_back fallback_location: ai_quota_path
  end

  # Bulk counterpart of the toggle: switching off the accounts that have nothing
  # left is the single most common action on this screen.
  def bulk_toggle
    target = params[:to] == "on"
    changed = AiAccount.where(active: !target).select { |a| bulk_match?(a, target) }
    changed.each { |a| a.update!(active: target) }
    audit!("ai_account.bulk_#{params[:to]}", count: changed.size)

    redirect_to ai_quota_path,
      notice: "#{changed.size} #{'conta'.pluralize(changed.size)} #{target ? 'ligada' : 'desligada'}#{'s' if changed.size != 1}"
  end

  # Adopts whatever credentials the CLIs on this host already hold — the way
  # this screen gets its first accounts without an OAuth flow.
  def import_local
    accounts = AiQuota::ImportLocal.call

    if accounts.any?
      redirect_to ai_quota_path, notice: "#{helpers.pluralize(accounts.size, 'conta')} importada#{'s' if accounts.size != 1}"
    else
      redirect_to ai_quota_path, alert: "Nenhuma credencial local encontrada (~/.claude, ~/.codex)"
    end
  end

  def refresh
    AiQuota::Usage.for(@account, force: true)
    redirect_back fallback_location: ai_quota_path
  end

  # Login PKCE independente por conta — ao contrário de import_local, não
  # depende do CLI do host estar logado numa conta só. Ver
  # AiQuota::ConnectClaude e docs/specs/feature-ai-quota.md (fase A6).
  def new_claude_login
    @verifier = AiQuota::ConnectClaude.new_verifier
    session[:claude_oauth_verifier] = @verifier
    @authorize_url = AiQuota::ConnectClaude.authorize_url(@verifier)
  end

  def create_claude_login
    verifier = session.delete(:claude_oauth_verifier)
    credential = verifier.present? ? AiQuota::ConnectClaude.exchange!(params[:code], verifier) : nil

    if credential
      account = AiQuota::ConnectClaude.create_account!(credential)
      audit!("ai_account.connect", account: account)
      redirect_to ai_quota_path, notice: "Conta Claude conectada"
    else
      redirect_to new_claude_login_ai_quota_path, alert: "Código inválido ou expirado — tente de novo"
    end
  end

  def new_ollama_key
  end

  def create_ollama_key
    key = params[:api_key].to_s.strip
    name = params[:name].to_s.strip.presence || "Ollama"

    if key.present?
      account = AiAccount.create!(
        provider: "ollama",
        credential_source: "inline",
        name: name,
        credential: { "apiKey" => key }
      )
      audit!("ai_account.connect", account: account)
      redirect_to ai_quota_path, notice: "Conta Ollama configurada"
    else
      redirect_to new_ollama_key_ai_quota_path, alert: "Chave de API não informada"
    end
  end

  def destroy
    @account.destroy!
    audit!("ai_account.destroy")
    redirect_to ai_quota_path, notice: "Conta removida"
  end

  private

  def filtered_accounts
    scope = AiAccount.by_priority
    scope = scope.where(provider: params[:provider]) if params[:provider].present?
    scope = scope.where(active: params[:status] == "active") if %w[active off].include?(params[:status])
    scope
  end

  # "Empty" here means what the card shows as empty: at least one exhausted
  # window. Turning accounts back on uses the inverse — nothing exhausted.
  def bulk_match?(account, turning_on)
    empty = AiQuota::Usage.for(account).any_empty?
    turning_on ? !empty : empty
  end

  def set_account
    @account = AiAccount.find(params[:id])
  end

  def audit!(action, account: @account, **details)
    AuditLog.record(
      user: Current.user, action: action,
      target_type: "AiAccount", target_id: account&.id,
      metadata: { provider: account&.provider, label: account&.label }.compact.merge(details),
      ip_address: request.remote_ip
    )
  end
end

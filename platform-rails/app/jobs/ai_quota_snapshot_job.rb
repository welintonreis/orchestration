# Records where every quota stood, so the platform can show a trend the
# providers themselves don't keep.
#
# Runs every 15 minutes: often enough to see a 5h window drain, rare enough to
# stay inside Anthropic's rate limit (its fetcher caches for 5 min, so a tighter
# schedule would mostly re-record the same cached numbers anyway).
class AiQuotaSnapshotJob < ApplicationJob
  queue_as :default

  def perform
    captured_at = Time.current

    AiAccount.active.find_each do |account|
      result = AiQuota::Usage.for(account)
      next unless result.ok?

      rows = result.quotas.map do |quota|
        {
          ai_account_id: account.id,
          quota_name: quota.name, model_key: quota.model_key,
          used: quota.used, total: quota.total, remaining_pct: quota.remaining_pct,
          reset_at: quota.reset_at, captured_at: captured_at, created_at: captured_at
        }
      end

      AiQuotaSnapshot.insert_all(rows) if rows.any?
    rescue StandardError => e
      # One unreachable provider must not stop the others from being recorded.
      Rails.logger.warn("[ai_quota_snapshot] #{account.provider}##{account.id}: #{e.message}")
    end

    AiQuotaSnapshot.stale.delete_all
  end
end

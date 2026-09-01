# One reading of one quota window at one moment.
#
# The providers expose only "right now" — none of them keeps history, so this
# table is the only place a trend can come from. That's also why it's write-once:
# editing a snapshot would be falsifying a measurement.
class AiQuotaSnapshot < ApplicationRecord
  RETENTION = 90.days

  belongs_to :ai_account

  scope :recent, -> { order(captured_at: :desc) }
  scope :stale, -> { where(captured_at: ...RETENTION.ago) }

  # Points for one window's sparkline, oldest first.
  def self.series_for(account, quota_name, limit: 48)
    where(ai_account: account, quota_name: quota_name)
      .recent.limit(limit).pluck(:captured_at, :remaining_pct)
      .reverse
  end
end

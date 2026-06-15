class HostMetric < ApplicationRecord
  validates :cpu_percent, :ram_percent, :disk_percent,
            :load_1m, :load_5m, :load_15m,
            presence: true, numericality: { greater_than_or_equal_to: 0 }

  scope :last_24h, -> { where(created_at: 24.hours.ago..) }

  def self.latest
    order(created_at: :desc).first
  end
end

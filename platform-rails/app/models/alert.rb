class Alert < ApplicationRecord
  LEVELS = %w[info warning critical].freeze

  validates :level, inclusion: { in: LEVELS }
  validates :resource, :message, presence: true

  scope :unread,       -> { where(read_at: nil) }
  scope :critical,     -> { where(level: "critical") }
  scope :by_resource,  ->(r) { where(resource: r) }
  scope :recent,       -> { order(created_at: :desc) }

  def read? = read_at.present?

  def mark_read!
    update!(read_at: Time.current)
  end

  def self.mark_all_read!
    unread.update_all(read_at: Time.current)
  end
end

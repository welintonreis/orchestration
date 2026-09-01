class VpsTerminalSession < ApplicationRecord
  belongs_to :user
  belongs_to :vps_host

  STATUSES = %w[connecting connected disconnected error].freeze

  validates :token, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }

  scope :active, -> { where(status: %w[connecting connected]) }
  scope :recent, -> { order(created_at: :desc) }

  before_validation :generate_token, on: :create
  before_validation :assign_slot,    on: :create

  def connected?
    status == "connected"
  end

  def mark_connected!
    update!(status: "connected", started_at: Time.current)
  end

  def mark_disconnected!(error: nil)
    update!(status: error ? "error" : "disconnected", ended_at: Time.current, error_message: error)
  end

  private

  def generate_token
    self.token ||= SecureRandom.uuid
  end

  # Each concurrent session (tab) on a host gets its own persistence slot so
  # tabs don't share one dtach/tmux shell. Lowest free slot: closing tab 2 and
  # opening a new one re-attaches slot 1's surviving shell.
  def assign_slot
    return if slot.to_i.positive? || vps_host.nil?
    taken = vps_host.vps_terminal_sessions.active.where.not(id: id).pluck(:slot).compact
    self.slot = (0..).find { |n| !taken.include?(n) }
  end
end

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
  before_create :set_uuid_id

  def connected?
    status == "connected"
  end

  def mark_connected!
    update!(status: "connected", started_at: Time.current)
    broadcast_status
  end

  def mark_disconnected!(error: nil)
    update!(status: error ? "error" : "disconnected", ended_at: Time.current, error_message: error)
    broadcast_status
  end

  private

  def set_uuid_id
    self.id ||= SecureRandom.uuid
  end

  # The UI's "Conectado" otherwise comes only from the ActionCable subscribe
  # handshake (vps_terminal_controller.js `connected:`), which fires before
  # SSH auth/PTY/exec even run. Push the real backend status down the same
  # stream VpsTerminalChannel already uses, so a slow or failed handshake
  # doesn't leave the label lying while the screen stays blank.
  def broadcast_status
    ActionCable.server.broadcast("vps_terminal_#{token}", { status: status, message: error_message }.compact)
  end

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

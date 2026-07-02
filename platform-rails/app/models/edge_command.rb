# Offline-tolerant command queue: hub enqueues (kind, payload), agent polls
# for pending commands on every heartbeat and acks with a result. Row-based
# instead of push-only so a command survives the node being offline —
# it just sits pending until the node's next heartbeat.
class EdgeCommand < ApplicationRecord
  DEFAULT_TTL = 24.hours

  STATUSES = %w[pending acked expired].freeze

  belongs_to :edge_node

  validates :kind, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: "pending").where("expires_at > ?", Time.current) }

  before_validation :assign_default_expiry, on: :create

  def self.enqueue!(edge_node:, kind:, payload: {}, ttl: DEFAULT_TTL)
    create!(edge_node: edge_node, kind: kind, payload: payload.to_json, expires_at: ttl.from_now)
  end

  # Expired-but-still-pending rows get flagged and alerted once, so the
  # `pending` scope (and thus the agent's poll response) stops surfacing
  # them without needing a delete.
  def self.expire_stale!
    stale = where(status: "pending").where("expires_at <= ?", Time.current)
    stale.find_each do |cmd|
      cmd.update!(status: "expired")
      Alert.create!(
        level:    "warning",
        resource: "edge_command",
        message:  "Edge command \"#{cmd.kind}\" on node #{cmd.edge_node.name} expired unacknowledged."
      )
    end
  end

  def payload_data
    JSON.parse(payload.presence || "{}")
  rescue JSON::ParserError
    {}
  end

  def result_data
    JSON.parse(result.presence || "{}")
  rescue JSON::ParserError
    {}
  end

  def ack!(result_data = {})
    update!(status: "acked", result: result_data.to_json)
  end

  private

  def assign_default_expiry
    self.expires_at ||= DEFAULT_TTL.from_now
  end
end

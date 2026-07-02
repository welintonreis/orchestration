require "digest"
require "securerandom"

# One remote Docker/Podman host enrolled via the agent (agent/). The node
# never receives inbound connections — it dials out to
# Api::EdgeTunnelsController and this row is how the hub recognizes it.
class EdgeNode < ApplicationRecord
  ONLINE_WINDOW = 90.seconds # 3x the agent's default 30s heartbeat

  belongs_to :environment
  has_many :edge_commands, dependent: :destroy
  has_many :host_metrics, dependent: :nullify

  validates :name, presence: true
  validates :uuid, presence: true, uniqueness: true
  validates :token_digest, presence: true, uniqueness: true

  before_validation :assign_uuid, on: :create

  scope :active, -> { where(revoked_at: nil) }

  # Creates the node + its backing Environment together, returns the RAW
  # permanent token — shown to the operator exactly once (enrollment
  # response), never persisted in plaintext.
  #
  # `uuid` defaults to a fresh one (admin-triggered manual enrollment) but
  # the token-based agent flow passes the uuid embedded in the enrollment
  # token — see EdgeEnrollmentToken for why that's the single-use guard.
  def self.enroll!(name:, uuid: SecureRandom.uuid)
    raw_token = SecureRandom.hex(32)
    node = nil
    ActiveRecord::Base.transaction do
      env = Environment.create!(
        name:          "edge/#{name}",
        endpoint_type: "edge",
        endpoint:      "edge://#{uuid}"
      )
      node = create!(name: name, uuid: uuid, token_digest: digest(raw_token), environment: env)
    end
    [node, raw_token]
  end

  def self.digest(raw_token) = Digest::SHA256.hexdigest(raw_token)

  def self.authenticate(raw_token)
    active.find_by(token_digest: digest(raw_token))
  end

  def revoke!
    update!(revoked_at: Time.current)
  end

  def revoked? = revoked_at.present?

  def online?
    !revoked? && last_seen_at.present? && last_seen_at > ONLINE_WINDOW.ago
  end

  def status
    return "revoked" if revoked?
    online? ? "online" : "offline"
  end

  def touch_heartbeat!(agent_version: nil, os: nil, arch: nil)
    update!(
      last_seen_at:  Time.current,
      agent_version: agent_version.presence || self.agent_version,
      os:            os.presence || self.os,
      arch:          arch.presence || self.arch
    )
  end

  private

  def assign_uuid
    self.uuid ||= SecureRandom.uuid
  end
end

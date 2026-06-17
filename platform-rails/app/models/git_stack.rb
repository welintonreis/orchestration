class GitStack < ApplicationRecord
  DEPLOY_MODES = %w[swarm_stack compose].freeze
  STATUSES     = %w[idle deploying deployed failed].freeze
  SOURCE_TYPES = %w[git yaml zip].freeze

  belongs_to :environment
  belongs_to :git_connection, optional: true

  validates :name, presence: true
  validates :source_type, inclusion: { in: SOURCE_TYPES }
  validates :compose_file, presence: true
  validates :deploy_mode, inclusion: { in: DEPLOY_MODES }
  validates :status, inclusion: { in: STATUSES }
  validates :git_connection_id, presence: true, if: -> { source_type == "git" }
  validates :yaml_content, presence: true, if: -> { source_type == "yaml" }

  before_create :generate_webhook_token
  before_create :generate_uuid

  # URLs show the uuid (git_stacks/<uuid>) instead of the sequential
  # integer PK — keeps the PK itself untouched (no FK migration risk)
  # while not leaking "stack #1" / enumerable IDs in the address bar.
  def to_param = uuid

  def webhook_url(base_url)
    "#{base_url}/webhooks/#{webhook_token}/deploy"
  end

  private

  def generate_webhook_token
    self.webhook_token = SecureRandom.hex(32)
  end

  def generate_uuid
    self.uuid = SecureRandom.uuid
  end
end

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

  def webhook_url(base_url)
    "#{base_url}/webhooks/#{webhook_token}/deploy"
  end

  private

  def generate_webhook_token
    self.webhook_token = SecureRandom.hex(32)
  end
end

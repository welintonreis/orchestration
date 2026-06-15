class GitStack < ApplicationRecord
  DEPLOY_MODES = %w[swarm_stack compose].freeze
  STATUSES     = %w[idle deploying deployed failed].freeze

  belongs_to :environment
  belongs_to :git_connection

  validates :name, presence: true
  validates :compose_file, presence: true
  validates :deploy_mode, inclusion: { in: DEPLOY_MODES }
  validates :status, inclusion: { in: STATUSES }

  before_create :generate_webhook_token

  def webhook_url(base_url)
    "#{base_url}/webhooks/#{webhook_token}/deploy"
  end

  private

  def generate_webhook_token
    self.webhook_token = SecureRandom.hex(32)
  end
end

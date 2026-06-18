class GitStack < ApplicationRecord
  DEPLOY_MODES = %w[swarm_stack compose].freeze
  STATUSES     = %w[idle deploying deployed failed].freeze
  SOURCE_TYPES = %w[git yaml zip].freeze

  belongs_to :environment
  belongs_to :git_credential, optional: true

  validates :name, presence: true
  validates :source_type, inclusion: { in: SOURCE_TYPES }
  validates :compose_file, presence: true
  validates :deploy_mode, inclusion: { in: DEPLOY_MODES }
  validates :status, inclusion: { in: STATUSES }
  validates :repo_url, presence: true, if: -> { source_type == "git" }
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

  # Credential to clone with — a saved GitCredential if one's attached,
  # otherwise the inline username/token entered on this stack directly
  # (the "fill it in now, don't save it" path from the deploy wizard).
  def auth_username = git_credential&.username || username
  def auth_token     = git_credential&.token    || token_ciphertext
  def ssh_key         = git_credential&.ssh_key
  def auth_type
    return git_credential.auth_type if git_credential
    auth_token.present? ? "token" : "none"
  end

  def authenticated_url
    return repo_url unless auth_type == "token"
    uri = URI.parse(repo_url)
    # URI's user=/password= setters require pre-escaped values — they don't
    # escape for you. An unescaped "@" in an email-as-username (a common
    # case for self-hosted GitLab) raises URI::InvalidComponentError.
    uri.user     = URI.encode_www_form_component(auth_username)
    uri.password = URI.encode_www_form_component(auth_token)
    uri.to_s
  rescue URI::Error
    repo_url
  end

  private

  def generate_webhook_token
    self.webhook_token = SecureRandom.hex(32)
  end

  def generate_uuid
    self.uuid = SecureRandom.uuid
  end
end

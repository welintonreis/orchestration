class GitStack < ApplicationRecord
  DEPLOY_MODES  = %w[swarm_stack compose].freeze
  STATUSES      = %w[idle deploying deployed failed].freeze
  SOURCE_TYPES  = %w[git yaml zip].freeze
  SYNC_STATUSES = %w[synced out_of_sync unknown].freeze
  HEALTH_STATES = %w[healthy progressing degraded missing unknown].freeze

  belongs_to :environment
  belongs_to :git_credential, optional: true
  has_many :revisions, -> { recent }, class_name: "GitStackRevision", dependent: :destroy

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
  def auth_token    = git_credential&.token    || token_ciphertext
  def ssh_key       = git_credential&.ssh_key

  def ci_token = ci_token_ciphertext
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

  def out_of_sync? = sync_status == "out_of_sync"

  # Parsed last drift diff for the UI. Shape: {"services" => [...], ...}.
  def drift
    return {} if drift_detail.blank?
    JSON.parse(drift_detail)
  rescue JSON::ParserError
    {}
  end

  # Sync window gates auto/self-heal deploys to an allowed time range.
  # Format: "<dow>-<dow> HH:MM-HH:MM" (e.g. "mon-fri 08:00-20:00"); blank =
  # always open. Manual deploys bypass this entirely.
  DOW = %w[sun mon tue wed thu fri sat].freeze

  def within_sync_window?(now = Time.current)
    spec = sync_window.to_s.strip.downcase
    return true if spec.blank?

    days, hours = spec.split(/\s+/, 2)
    return true if hours.blank?

    return false unless day_in_range?(days, now.wday)

    from, to = hours.split("-", 2).map { |h| minutes_of_day(h) }
    return true if from.nil? || to.nil?
    cur = now.hour * 60 + now.min
    from <= to ? cur.between?(from, to) : (cur >= from || cur <= to)
  rescue StandardError
    true # never block a deploy on a malformed window
  end

  private

  def day_in_range?(days, wday)
    a, b = days.split("-", 2)
    ai = DOW.index(a)
    return true if ai.nil?
    bi = b ? DOW.index(b) : ai
    return true if bi.nil?
    ai <= bi ? wday.between?(ai, bi) : (wday >= ai || wday <= bi)
  end

  def minutes_of_day(hhmm)
    h, m = hhmm.to_s.split(":", 2)
    return nil if h.nil?
    h.to_i * 60 + m.to_i
  end

  def generate_webhook_token
    self.webhook_token = SecureRandom.hex(32)
  end

  def generate_uuid
    self.uuid = SecureRandom.uuid
  end
end

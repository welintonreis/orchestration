class User < ApplicationRecord
  ROLES = %w[admin operator readonly].freeze

  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :audit_logs, dependent: :nullify
  has_many :team_memberships, dependent: :destroy
  has_many :teams, through: :team_memberships
  has_many :vps_terminal_sessions, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :role, inclusion: { in: ROLES }
  before_validation :set_default_role

  scope :active_users, -> { where(active: true) }

  def admin?    = role == "admin"
  def operator? = role == "operator"
  def readonly? = role == "readonly"

  def has_avatar?
    avatar_data.present?
  end

  def avatar_data_uri
    return nil unless has_avatar?
    "data:#{avatar_content_type || 'image/png'};base64,#{Base64.strict_encode64(avatar_data)}"
  end

  def avatar=(uploaded_file)
    if uploaded_file.present? && uploaded_file.respond_to?(:read)
      self.avatar_data = uploaded_file.read
      self.avatar_content_type = uploaded_file.content_type.presence || "image/png"
    elsif uploaded_file == ""
      self.avatar_data = nil
      self.avatar_content_type = nil
    end
  end

  private

  def set_default_role
    self.role ||= "admin"
  end
end

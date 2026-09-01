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

  private

  def set_default_role
    self.role ||= "admin"
  end
end

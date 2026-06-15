class User < ApplicationRecord
  ROLES = %w[admin operator readonly].freeze

  has_secure_password
  has_many :sessions, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :role, inclusion: { in: ROLES }
  before_validation :set_default_role

  def admin? = role == "admin"
  def operator? = role == "operator"
  def readonly? = role == "readonly"

  private

  def set_default_role
    self.role ||= "admin"
  end
end

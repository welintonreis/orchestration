class Environment < ApplicationRecord
  ENDPOINT_TYPES = %w[unix tcp].freeze

  validates :name, presence: true, uniqueness: true
  validates :endpoint_type, inclusion: { in: ENDPOINT_TYPES }
  validates :endpoint, presence: true, format: {
    with: /\A(unix:\/\/\/|tcp:\/\/).+/,
    message: "must start with unix:/// or tcp://"
  }

  scope :active_env, -> { where(active: true).first }

  def unix? = endpoint_type == "unix"
  def tcp?  = endpoint_type == "tcp"

  def activate!
    Environment.update_all(active: false)
    update!(active: true)
  end
end

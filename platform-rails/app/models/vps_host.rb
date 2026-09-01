class VpsHost < ApplicationRecord
  belongs_to :shared_credential
  has_many :vps_terminal_sessions, dependent: :destroy

  AUTH_METHODS = %w[password key key_with_passphrase].freeze

  validates :name, presence: true, uniqueness: true
  validates :hostname, presence: true
  validates :port, numericality: { in: 1..65535 }, allow_nil: false
  validates :username, presence: true
  validates :auth_method, inclusion: { in: AUTH_METHODS }

  scope :recent, -> { order(last_connected_at: :desc) }
  scope :by_name, -> { order(:name) }
end

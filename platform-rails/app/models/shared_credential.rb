class SharedCredential < ApplicationRecord
  TYPES = %w[ssh_key password api_token tls_cert].freeze
  validates :name, presence: true, uniqueness: true
  validates :credential_type, inclusion: { in: TYPES }
  validates :username, presence: true
  validates :encrypted_secret, presence: true
end

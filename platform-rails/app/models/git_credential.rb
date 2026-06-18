class GitCredential < ApplicationRecord
  AUTH_TYPES = %w[token ssh_key].freeze

  has_many :git_stacks, dependent: :nullify

  validates :name, presence: true, uniqueness: true
  validates :site, presence: true
  validates :auth_type, inclusion: { in: AUTH_TYPES }
  validates :username, presence: true, if: -> { auth_type == "token" }
  validates :token_ciphertext, presence: true, if: -> { auth_type == "token" }
  validates :ssh_key_ciphertext, presence: true, if: -> { auth_type == "ssh_key" }

  def token = token_ciphertext    # plain storage for now, encrypted_attr in future
  def ssh_key = ssh_key_ciphertext
end

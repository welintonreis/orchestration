class GitConnection < ApplicationRecord
  AUTH_TYPES = %w[none token ssh_key].freeze

  has_many :git_stacks, dependent: :destroy

  validates :name, presence: true, uniqueness: true
  validates :repo_url, presence: true, format: { with: /\Ahttps?:\/\/.+|git@.+/, message: "must be HTTP(S) or SSH URL" }
  validates :auth_type, inclusion: { in: AUTH_TYPES }
  validates :username, presence: true, if: -> { auth_type == "token" }
  validates :token_ciphertext, presence: true, if: -> { auth_type == "token" }
  validates :ssh_key_ciphertext, presence: true, if: -> { auth_type == "ssh_key" }

  def token = token_ciphertext    # plain storage for now, encrypted_attr in future
  def ssh_key = ssh_key_ciphertext

  def authenticated_url
    return repo_url unless auth_type == "token"
    uri = URI.parse(repo_url)
    # URI's user=/password= setters require pre-escaped values — they don't
    # escape for you. An unescaped "@" in an email-as-username (a common
    # case for self-hosted GitLab) raises URI::InvalidComponentError, which
    # this used to not even rescue (only InvalidURIError was caught).
    uri.user     = URI.encode_www_form_component(username)
    uri.password = URI.encode_www_form_component(token_ciphertext)
    uri.to_s
  rescue URI::Error
    repo_url
  end
end

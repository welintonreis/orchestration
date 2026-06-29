class SwarmRegistry < ApplicationRecord
  API_TYPES = %w[docker_hub quay generic_v2].freeze

  validates :name, presence: true, uniqueness: true
  validates :url,  presence: true
  validates :username, presence: true, unless: :public?
  validates :api_type, inclusion: { in: API_TYPES }, allow_blank: true

  scope :public_registries,  -> { where(public: true) }
  scope :private_registries, -> { where(public: false) }
  scope :searchable,         -> { where.not(api_type: [nil, ""]) }

  def searchable? = api_type.present?

  def display_url
    url.gsub(%r{://.*:.*@}, "://***:***@")
  end

  def api_label
    { "docker_hub" => "Docker Hub", "quay" => "Quay.io", "generic_v2" => "Registry v2" }[api_type] || api_type
  end
end

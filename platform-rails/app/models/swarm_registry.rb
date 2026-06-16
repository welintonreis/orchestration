class SwarmRegistry < ApplicationRecord
  validates :name, presence: true, uniqueness: true
  validates :url, presence: true

  def display_url
    url.gsub(%r{://.*:.*@}, "://***:***@")
  end
end

class EnvironmentRegistry < ApplicationRecord
  belongs_to :environment
  validates :url, presence: true
  validates :username, presence: true
end

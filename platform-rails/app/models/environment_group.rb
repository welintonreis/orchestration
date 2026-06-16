class EnvironmentGroup < ApplicationRecord
  has_many :environment_group_memberships, dependent: :destroy
  has_many :environments, through: :environment_group_memberships
  validates :name, presence: true, uniqueness: true
end

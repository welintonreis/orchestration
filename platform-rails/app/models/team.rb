class Team < ApplicationRecord
  has_many :team_memberships, dependent: :destroy
  has_many :users, through: :team_memberships

  validates :name, presence: true, uniqueness: true
end

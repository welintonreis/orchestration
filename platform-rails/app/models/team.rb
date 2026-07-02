class Team < ApplicationRecord
  has_many :team_memberships, dependent: :destroy
  has_many :users, through: :team_memberships
  has_many :team_environment_permissions, dependent: :destroy
  has_many :environments, through: :team_environment_permissions

  validates :name, presence: true, uniqueness: true

  # Opt-in marker: does this team have ANY per-environment scoping at all?
  # See Authorization#effective_role for what this gates.
  def environment_scoped?
    team_environment_permissions.exists?
  end
end

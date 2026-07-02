# Opt-in, per-team environment scoping (see Authorization#effective_role).
# A team with zero rows here is unrestricted — every environment, at its
# global role — exactly today's behavior. The moment a team gets even one
# row, it becomes scoped: environments without an explicit row for that
# team are denied, not just capped at readonly.
class TeamEnvironmentPermission < ApplicationRecord
  ROLES = %w[readonly operator admin].freeze

  belongs_to :team
  belongs_to :environment

  validates :role, inclusion: { in: ROLES }
  validates :team_id, uniqueness: { scope: :environment_id }
end

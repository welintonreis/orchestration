class EnvironmentGroupMembership < ApplicationRecord
  belongs_to :environment
  belongs_to :environment_group
end

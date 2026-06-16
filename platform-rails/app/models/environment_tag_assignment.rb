class EnvironmentTagAssignment < ApplicationRecord
  belongs_to :environment
  belongs_to :environment_tag
end

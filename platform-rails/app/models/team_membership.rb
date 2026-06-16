class TeamMembership < ApplicationRecord
  belongs_to :team
  belongs_to :user

  ROLES = %w[member lead].freeze
  validates :role, inclusion: { in: ROLES }, allow_blank: true

  after_initialize { self.role ||= "member" }
end

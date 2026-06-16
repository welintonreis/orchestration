class EnvironmentTag < ApplicationRecord
  has_many :environment_tag_assignments, dependent: :destroy
  has_many :environments, through: :environment_tag_assignments
  validates :name, presence: true, uniqueness: true
  validates :color, format: { with: /\A#[0-9a-fA-F]{6}\z/, message: "must be hex color" }, allow_blank: true
  before_validation { self.color = "#6366f1" if color.blank? }
end

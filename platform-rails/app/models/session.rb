class Session < ApplicationRecord
  belongs_to :user
  before_create :set_uuid_id

  private

  def set_uuid_id
    self.id ||= SecureRandom.uuid
  end
end

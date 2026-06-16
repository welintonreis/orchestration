class AppSetting < ApplicationRecord
  validates :key, presence: true, uniqueness: true

  def self.get(key, default: nil)
    find_by(key: key)&.value || default
  end

  def self.set(key, value, description: nil)
    find_or_initialize_by(key: key).tap { |s| s.update!(value: value.to_s, description: description) }
  end
end

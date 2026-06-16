class AppAsset < ApplicationRecord
  validates :key, presence: true, uniqueness: true
  validates :content_type, presence: true
  validates :data, presence: true

  def self.store(key:, data:, content_type:)
    find_or_initialize_by(key: key).tap do |a|
      a.update!(data: data, content_type: content_type)
    end
  end
end

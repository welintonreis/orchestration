class AuditLog < ApplicationRecord
  belongs_to :user

  scope :recent, -> { order(created_at: :desc) }

  def self.record(user:, action:, target_type: nil, target_id: nil, metadata: {}, ip_address: nil)
    create!(
      user:        user,
      action:      action,
      target_type: target_type,
      target_id:   target_id&.to_s,
      metadata:    metadata,
      ip_address:  ip_address
    )
  rescue => e
    Rails.logger.error "AuditLog.record failed: #{e.message}"
  end
end

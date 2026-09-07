class BackupSnapshot < ApplicationRecord
  scope :recent_first, -> { order(captured_at: :desc) }
end

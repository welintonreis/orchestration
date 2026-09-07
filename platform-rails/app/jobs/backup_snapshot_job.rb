class BackupSnapshotJob < ApplicationJob
  queue_as :default

  def perform
    result = WalgInspectorService.call
    latest = result.backups.first

    BackupSnapshot.create!(
      server: "master",
      total_bytes: result.total_bytes,
      object_count: result.object_count,
      last_backup_name: latest&.name,
      last_backup_type: latest&.type,
      last_backup_at: latest&.time,
      error: result.ok? ? nil : result.error,
      captured_at: Time.current
    )
  end
end

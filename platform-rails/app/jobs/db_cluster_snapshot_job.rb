class DbClusterSnapshotJob < ApplicationJob
  queue_as :default

  def perform
    DbClusterInspectorService.call.each do |row|
      DbClusterSnapshot.create!(
        server: row.server, database_name: row.database,
        row_count: row.estimated_rows, captured_at: Time.current
      )
    end
  end
end

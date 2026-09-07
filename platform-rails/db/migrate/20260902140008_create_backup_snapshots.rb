class CreateBackupSnapshots < ActiveRecord::Migration[8.0]
  def change
    create_table :backup_snapshots do |t|
      t.string   :server,           null: false # sempre "master" nesta fase
      t.bigint   :total_bytes
      t.integer  :object_count
      t.string   :last_backup_name
      t.string   :last_backup_type # "FULL" | "DELTA"
      t.datetime :last_backup_at
      t.text     :error
      t.datetime :captured_at, null: false

      t.timestamps
    end
    add_index :backup_snapshots, [:server, :captured_at], name: "index_backup_snapshots_lookup"
  end
end

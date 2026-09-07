class CreateDbClusterSnapshots < ActiveRecord::Migration[8.0]
  def change
    create_table :db_cluster_snapshots do |t|
      t.string   :server,        null: false # "master" | "analytics"
      t.string   :database_name, null: false
      t.bigint   :row_count,     null: false
      t.datetime :captured_at,   null: false

      t.timestamps
    end
    add_index :db_cluster_snapshots, [:server, :database_name, :captured_at],
              name: "index_db_cluster_snapshots_lookup"
  end
end

class CreateEdgeCommands < ActiveRecord::Migration[8.1]
  def change
    create_table :edge_commands do |t|
      t.references :edge_node, null: false, foreign_key: true
      t.string   :kind, null: false          # e.g. "open_stream"
      t.text     :payload                    # JSON
      t.string   :status, default: "pending", null: false # pending | acked | expired
      t.text     :result                     # JSON, filled on ack
      t.datetime :expires_at, null: false

      t.timestamps
    end
    add_index :edge_commands, [:edge_node_id, :status]
  end
end

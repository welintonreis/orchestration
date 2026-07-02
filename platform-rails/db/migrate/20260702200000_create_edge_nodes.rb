class CreateEdgeNodes < ActiveRecord::Migration[8.1]
  def change
    create_table :edge_nodes do |t|
      t.string   :uuid, null: false
      t.string   :name, null: false
      t.string   :token_digest, null: false
      t.string   :agent_version
      t.string   :os
      t.string   :arch
      t.datetime :last_seen_at
      t.datetime :revoked_at
      t.references :environment, null: false, foreign_key: true

      t.timestamps
    end
    add_index :edge_nodes, :uuid, unique: true
    add_index :edge_nodes, :token_digest, unique: true
  end
end

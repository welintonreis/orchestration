class CreateAiQuotaSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_quota_snapshots do |t|
      t.references :ai_account, null: false, foreign_key: true
      t.string   :quota_name, null: false
      t.string   :model_key
      t.integer  :used
      t.integer  :total
      t.integer  :remaining_pct
      t.datetime :reset_at
      t.datetime :captured_at, null: false

      # No updated_at: a snapshot is a fact about a moment, never edited.
      t.datetime :created_at, null: false
    end

    add_index :ai_quota_snapshots, [ :ai_account_id, :quota_name, :captured_at ],
              name: "index_ai_quota_snapshots_on_account_quota_time"
  end
end

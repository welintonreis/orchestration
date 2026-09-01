class CreateVpsTerminalSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :vps_terminal_sessions, id: :uuid do |t|
      t.references :vps_host, null: false, foreign_key: true, type: :uuid
      t.references :user, null: false, foreign_key: true
      t.string   :token, null: false
      t.string   :status, null: false, default: "connecting"
      t.integer  :slot, default: 0
      t.integer  :terminal_cols
      t.integer  :terminal_rows
      t.text     :error_message
      t.datetime :started_at
      t.datetime :ended_at

      t.timestamps
    end
    add_index :vps_terminal_sessions, :token, unique: true
  end
end

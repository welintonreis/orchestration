class CreateAuditLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_logs do |t|
      t.references :user, null: false, foreign_key: true
      t.string :action, null: false
      t.string :target_type
      t.string :target_id
      t.json   :metadata, default: {}
      t.string :ip_address

      t.timestamps
    end

    add_index :audit_logs, :action
    add_index :audit_logs, :created_at
  end
end

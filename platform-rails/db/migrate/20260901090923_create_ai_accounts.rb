class CreateAiAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_accounts do |t|
      t.string  :provider,     null: false
      t.string  :auth_type,    null: false, default: "oauth"
      t.string  :name
      t.string  :email
      t.string  :display_name

      # Where the credential comes from: "file" (a CLI's credential file on
      # disk, which that CLI keeps refreshed) or "inline" (pasted here, and
      # ours to refresh).
      t.string  :credential_source, null: false, default: "inline"
      t.string  :credential_path

      t.text    :credentials              # encrypted JSON, nil when source is "file"
      t.json    :provider_data, default: {}

      t.integer :priority, default: 1
      t.boolean :active,   null: false, default: true

      t.string    :test_status
      t.string    :last_error
      t.datetime  :last_error_at
      t.datetime  :last_used_at

      t.timestamps
    end

    add_index :ai_accounts, :provider
    add_index :ai_accounts, [ :provider, :active ]
  end
end

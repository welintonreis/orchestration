class ConvertVpsAndSessionsToUuid < ActiveRecord::Migration[8.1]
  def up
    # 1. vps_hosts: add uuid string column
    add_column :vps_hosts, :uuid_id, :string
    execute "UPDATE vps_hosts SET uuid_id = lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-' || '4' || substr(hex(randomblob(2)),2) || '-' || substr('89ab', 1 + (abs(random()) % 4), 1) || substr(hex(randomblob(2)),2) || '-' || hex(randomblob(6)))"

    # 2. vps_terminal_sessions: map vps_host_id to uuid, add session uuid
    add_column :vps_terminal_sessions, :uuid_id, :string
    add_column :vps_terminal_sessions, :vps_host_uuid, :string

    execute <<-SQL
      UPDATE vps_terminal_sessions
      SET uuid_id = lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-' || '4' || substr(hex(randomblob(2)),2) || '-' || substr('89ab', 1 + (abs(random()) % 4), 1) || substr(hex(randomblob(2)),2) || '-' || hex(randomblob(6)))
    SQL

    execute <<-SQL
      UPDATE vps_terminal_sessions
      SET vps_host_uuid = (SELECT uuid_id FROM vps_hosts WHERE vps_hosts.id = vps_terminal_sessions.vps_host_id)
    SQL

    # 3. sessions: add uuid
    add_column :sessions, :uuid_id, :string
    execute "UPDATE sessions SET uuid_id = lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-' || '4' || substr(hex(randomblob(2)),2) || '-' || substr('89ab', 1 + (abs(random()) % 4), 1) || substr(hex(randomblob(2)),2) || '-' || hex(randomblob(6)))"

    # SQLite recreate tables with new PKs
    # vps_hosts
    create_table :vps_hosts_new, id: :string, primary_key: :id, force: :cascade do |t|
      t.string "auth_method", default: "password", null: false
      t.datetime "created_at", null: false
      t.text "description"
      t.string "host_key_fingerprint"
      t.string "hostname", null: false
      t.datetime "last_connected_at"
      t.string "name", null: false
      t.integer "port", default: 22, null: false
      t.integer "shared_credential_id"
      t.datetime "updated_at", null: false
      t.string "username", null: false
      t.index ["name"], name: "index_vps_hosts_on_name", unique: true
      t.index ["shared_credential_id"], name: "index_vps_hosts_on_shared_credential_id"
    end

    execute <<-SQL
      INSERT INTO vps_hosts_new (id, auth_method, created_at, description, host_key_fingerprint, hostname, last_connected_at, name, port, shared_credential_id, updated_at, username)
      SELECT uuid_id, auth_method, created_at, description, host_key_fingerprint, hostname, last_connected_at, name, port, shared_credential_id, updated_at, username
      FROM vps_hosts
    SQL
    drop_table :vps_hosts
    rename_table :vps_hosts_new, :vps_hosts

    # vps_terminal_sessions
    create_table :vps_terminal_sessions_new, id: :string, primary_key: :id, force: :cascade do |t|
      t.datetime "created_at", null: false
      t.datetime "ended_at"
      t.text "error_message"
      t.integer "slot", default: 0
      t.datetime "started_at"
      t.string "status", default: "connecting", null: false
      t.integer "terminal_cols"
      t.integer "terminal_rows"
      t.string "token", null: false
      t.datetime "updated_at", null: false
      t.integer "user_id", null: false
      t.string "vps_host_id", null: false
      t.index ["token"], name: "index_vps_terminal_sessions_on_token", unique: true
      t.index ["user_id"], name: "index_vps_terminal_sessions_on_user_id"
      t.index ["vps_host_id"], name: "index_vps_terminal_sessions_on_vps_host_id"
    end

    execute <<-SQL
      INSERT INTO vps_terminal_sessions_new (id, created_at, ended_at, error_message, slot, started_at, status, terminal_cols, terminal_rows, token, updated_at, user_id, vps_host_id)
      SELECT uuid_id, created_at, ended_at, error_message, slot, started_at, status, terminal_cols, terminal_rows, token, updated_at, user_id, vps_host_uuid
      FROM vps_terminal_sessions
    SQL
    drop_table :vps_terminal_sessions
    rename_table :vps_terminal_sessions_new, :vps_terminal_sessions

    # sessions
    create_table :sessions_new, id: :string, primary_key: :id, force: :cascade do |t|
      t.datetime "created_at", null: false
      t.string "ip_address"
      t.datetime "updated_at", null: false
      t.string "user_agent"
      t.integer "user_id", null: false
      t.index ["user_id"], name: "index_sessions_on_user_id"
    end

    execute <<-SQL
      INSERT INTO sessions_new (id, created_at, ip_address, updated_at, user_agent, user_id)
      SELECT uuid_id, created_at, ip_address, updated_at, user_agent, user_id
      FROM sessions
    SQL
    drop_table :sessions
    rename_table :sessions_new, :sessions
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end

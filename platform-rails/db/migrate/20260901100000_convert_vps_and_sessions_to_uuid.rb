class ConvertVpsAndSessionsToUuid < ActiveRecord::Migration[8.1]
  def up
    enable_extension "pgcrypto"

    # Clean up any partial state from previously failed run
    drop_table :vps_hosts_new if table_exists?(:vps_hosts_new)
    drop_table :vps_terminal_sessions_new if table_exists?(:vps_terminal_sessions_new)
    drop_table :sessions_new if table_exists?(:sessions_new)

    # 1. vps_hosts: add UUID column & populate
    add_column :vps_hosts, :uuid_id, :uuid, default: -> { "gen_random_uuid()" }, null: false unless column_exists?(:vps_hosts, :uuid_id)

    # 2. vps_terminal_sessions: add UUID columns & populate
    add_column :vps_terminal_sessions, :uuid_id, :uuid, default: -> { "gen_random_uuid()" }, null: false unless column_exists?(:vps_terminal_sessions, :uuid_id)
    add_column :vps_terminal_sessions, :vps_host_uuid, :uuid unless column_exists?(:vps_terminal_sessions, :vps_host_uuid)

    execute <<-SQL
      UPDATE vps_terminal_sessions
      SET vps_host_uuid = vps_hosts.uuid_id
      FROM vps_hosts
      WHERE vps_terminal_sessions.vps_host_id = vps_hosts.id
        AND vps_host_uuid IS NULL
    SQL

    # 3. sessions: add UUID column & populate
    add_column :sessions, :uuid_id, :uuid, default: -> { "gen_random_uuid()" }, null: false unless column_exists?(:sessions, :uuid_id)

    # --- Recreate vps_hosts ---
    create_table :vps_hosts_new, id: :uuid, primary_key: :id, force: :cascade do |t|
      t.string "auth_method", default: "password", null: false
      t.datetime "created_at", null: false
      t.text "description"
      t.string "host_key_fingerprint"
      t.string "hostname", null: false
      t.datetime "last_connected_at"
      t.string "name", null: false
      t.integer "port", default: 22, null: false
      t.bigint "shared_credential_id"
      t.datetime "updated_at", null: false
      t.string "username", null: false
    end

    execute <<-SQL
      INSERT INTO vps_hosts_new (id, auth_method, created_at, description, host_key_fingerprint, hostname, last_connected_at, name, port, shared_credential_id, updated_at, username)
      SELECT uuid_id, auth_method, created_at, description, host_key_fingerprint, hostname, last_connected_at, name, port, shared_credential_id, updated_at, username
      FROM vps_hosts
    SQL
    drop_table :vps_hosts
    rename_table :vps_hosts_new, :vps_hosts
    add_index :vps_hosts, :name, unique: true
    add_index :vps_hosts, :shared_credential_id

    # --- Recreate vps_terminal_sessions ---
    create_table :vps_terminal_sessions_new, id: :uuid, primary_key: :id, force: :cascade do |t|
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
      t.bigint "user_id", null: false
      t.uuid "vps_host_id", null: false
    end

    execute <<-SQL
      INSERT INTO vps_terminal_sessions_new (id, created_at, ended_at, error_message, slot, started_at, status, terminal_cols, terminal_rows, token, updated_at, user_id, vps_host_id)
      SELECT uuid_id, created_at, ended_at, error_message, slot, started_at, status, terminal_cols, terminal_rows, token, updated_at, user_id, vps_host_uuid
      FROM vps_terminal_sessions
    SQL
    drop_table :vps_terminal_sessions
    rename_table :vps_terminal_sessions_new, :vps_terminal_sessions
    add_index :vps_terminal_sessions, :token, unique: true
    add_index :vps_terminal_sessions, :user_id
    add_index :vps_terminal_sessions, :vps_host_id

    # --- Recreate sessions ---
    create_table :sessions_new, id: :uuid, primary_key: :id, force: :cascade do |t|
      t.datetime "created_at", null: false
      t.string "ip_address"
      t.datetime "updated_at", null: false
      t.string "user_agent"
      t.bigint "user_id", null: false
    end

    execute <<-SQL
      INSERT INTO sessions_new (id, created_at, updated_at, user_agent, user_id)
      SELECT uuid_id, created_at, updated_at, user_agent, user_id
      FROM sessions
    SQL
    drop_table :sessions
    rename_table :sessions_new, :sessions
    add_index :sessions, :user_id
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end

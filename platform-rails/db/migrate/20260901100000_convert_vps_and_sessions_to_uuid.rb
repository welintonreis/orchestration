class ConvertVpsAndSessionsToUuid < ActiveRecord::Migration[8.1]
  def up
    enable_extension "pgcrypto" unless extension_enabled?("pgcrypto")

    # 1. vps_terminal_sessions (leaf table)
    add_column :vps_terminal_sessions, :uuid_id, :uuid, default: -> { "gen_random_uuid()" }, null: false
    # 2. vps_hosts
    add_column :vps_hosts, :uuid_id, :uuid, default: -> { "gen_random_uuid()" }, null: false
    # 3. sessions
    add_column :sessions, :uuid_id, :uuid, default: -> { "gen_random_uuid()" }, null: false

    # Add new UUID FK columns to tables that point to vps_hosts
    add_column :vps_terminal_sessions, :vps_host_uuid, :uuid

    # Populate FK
    execute <<-SQL
      UPDATE vps_terminal_sessions
      SET vps_host_uuid = vps_hosts.uuid_id
      FROM vps_hosts
      WHERE vps_terminal_sessions.vps_host_id = vps_hosts.id
    SQL

    # Swap PK/FK for vps_terminal_sessions
    remove_foreign_key :vps_terminal_sessions, :vps_hosts if foreign_key_exists?(:vps_terminal_sessions, :vps_hosts)
    remove_foreign_key :vps_terminal_sessions, :users if foreign_key_exists?(:vps_terminal_sessions, :users)
    remove_column :vps_terminal_sessions, :vps_host_id
    rename_column :vps_terminal_sessions, :vps_host_uuid, :vps_host_id

    # Swap PK on vps_terminal_sessions
    execute "ALTER TABLE vps_terminal_sessions DROP CONSTRAINT vps_terminal_sessions_pkey CASCADE"
    remove_column :vps_terminal_sessions, :id
    rename_column :vps_terminal_sessions, :uuid_id, :id
    execute "ALTER TABLE vps_terminal_sessions ADD PRIMARY KEY (id)"

    # Swap PK on vps_hosts
    execute "ALTER TABLE vps_hosts DROP CONSTRAINT vps_hosts_pkey CASCADE"
    remove_column :vps_hosts, :id
    rename_column :vps_hosts, :uuid_id, :id
    execute "ALTER TABLE vps_hosts ADD PRIMARY KEY (id)"

    # Swap PK on sessions
    execute "ALTER TABLE sessions DROP CONSTRAINT sessions_pkey CASCADE"
    remove_column :sessions, :id
    rename_column :sessions, :uuid_id, :id
    execute "ALTER TABLE sessions ADD PRIMARY KEY (id)"

    # Recreate FKs
    add_foreign_key :vps_terminal_sessions, :vps_hosts, column: :vps_host_id
    add_index :vps_terminal_sessions, :vps_host_id unless index_exists?(:vps_terminal_sessions, :vps_host_id)
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "UUID swap is irreversible"
  end
end

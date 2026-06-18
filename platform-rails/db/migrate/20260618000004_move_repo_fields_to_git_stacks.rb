class MoveRepoFieldsToGitStacks < ActiveRecord::Migration[8.1]
  def up
    add_column :git_stacks, :repo_url, :string
    add_column :git_stacks, :branch, :string, default: "main"
    add_column :git_stacks, :last_commit_sha, :string
    add_column :git_stacks, :last_pulled_at, :datetime
    add_column :git_stacks, :git_credential_id, :integer
    add_column :git_stacks, :username, :string
    add_column :git_stacks, :token_ciphertext, :string
    add_index  :git_stacks, :git_credential_id

    # One GitConnection used to imply exactly one repo_url/branch — carry
    # that over to any pre-existing git_stacks (and point them at the
    # matching newly-created GitCredential by name) before the old
    # connection_id column + table go away.
    execute <<~SQL
      UPDATE git_stacks
      SET repo_url = (SELECT repo_url FROM git_connections WHERE git_connections.id = git_stacks.git_connection_id),
          branch    = (SELECT branch    FROM git_connections WHERE git_connections.id = git_stacks.git_connection_id),
          git_credential_id = (SELECT git_credentials.id FROM git_credentials
                                JOIN git_connections ON git_connections.name = git_credentials.name
                                WHERE git_connections.id = git_stacks.git_connection_id)
      WHERE git_connection_id IS NOT NULL
    SQL

    remove_index :git_stacks, :git_connection_id
    remove_column :git_stacks, :git_connection_id
    drop_table :git_connections
  end

  def down
    create_table :git_connections do |t|
      t.string :name, null: false
      t.string :repo_url, null: false
      t.string :branch, default: "main"
      t.string :auth_type, default: "none"
      t.string :username
      t.string :token_ciphertext
      t.text   :ssh_key_ciphertext
      t.string :last_commit_sha
      t.datetime :last_pulled_at
      t.timestamps
    end
    add_index :git_connections, :name, unique: true

    add_column :git_stacks, :git_connection_id, :integer
    add_index  :git_stacks, :git_connection_id

    remove_index  :git_stacks, :git_credential_id
    remove_column :git_stacks, :token_ciphertext
    remove_column :git_stacks, :username
    remove_column :git_stacks, :git_credential_id
    remove_column :git_stacks, :last_pulled_at
    remove_column :git_stacks, :last_commit_sha
    remove_column :git_stacks, :branch
    remove_column :git_stacks, :repo_url
  end
end

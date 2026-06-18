class CreateGitCredentials < ActiveRecord::Migration[8.1]
  def change
    create_table :git_credentials do |t|
      t.string :name, null: false
      t.string :site, null: false
      t.string :auth_type, default: "token", null: false
      t.string :username
      t.string :token_ciphertext
      t.text   :ssh_key_ciphertext

      t.timestamps
    end
    add_index :git_credentials, :name, unique: true

    reversible do |dir|
      dir.up do
        execute <<~SQL
          INSERT INTO git_credentials (name, site, auth_type, username, token_ciphertext, ssh_key_ciphertext, created_at, updated_at)
          SELECT name,
                 CASE WHEN repo_url LIKE 'http%' THEN
                   substr(repo_url, instr(repo_url, '://') + 3,
                     (CASE WHEN instr(substr(repo_url, instr(repo_url, '://') + 3), '/') = 0
                           THEN length(substr(repo_url, instr(repo_url, '://') + 3))
                           ELSE instr(substr(repo_url, instr(repo_url, '://') + 3), '/') - 1 END))
                 ELSE repo_url END,
                 auth_type, username, token_ciphertext, ssh_key_ciphertext, created_at, updated_at
          FROM git_connections
        SQL
      end
    end
  end
end

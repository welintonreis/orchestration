class CreateGitConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :git_connections do |t|
      t.string :name,              null: false
      t.string :repo_url,          null: false
      t.string :branch,            default: "main"
      t.string :auth_type,         default: "none"
      t.string :username
      t.string :token_ciphertext
      t.text   :ssh_key_ciphertext
      t.string :last_commit_sha
      t.datetime :last_pulled_at

      t.timestamps
    end

    add_index :git_connections, :name, unique: true
  end
end

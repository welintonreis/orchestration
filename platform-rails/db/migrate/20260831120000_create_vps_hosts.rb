class CreateVpsHosts < ActiveRecord::Migration[8.1]
  def change
    create_table :vps_hosts do |t|
      t.string   :name, null: false
      t.string   :hostname, null: false
      t.integer  :port, null: false, default: 22
      t.string   :username, null: false
      t.string   :auth_method, null: false, default: "password" # password | key | key_with_passphrase
      t.text     :description
      t.string   :host_key_fingerprint
      t.datetime :last_connected_at
      t.references :shared_credential, foreign_key: true

      t.timestamps
    end
    add_index :vps_hosts, :name, unique: true
  end
end

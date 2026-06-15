class CreateEnvironments < ActiveRecord::Migration[8.1]
  def change
    create_table :environments do |t|
      t.string :name, null: false
      t.string :endpoint_type, null: false, default: "unix"
      t.string :endpoint, null: false, default: "unix:///var/run/docker.sock"
      t.boolean :active, null: false, default: false

      t.timestamps
    end

    add_index :environments, :name, unique: true
  end
end

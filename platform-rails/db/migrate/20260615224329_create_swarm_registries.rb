class CreateSwarmRegistries < ActiveRecord::Migration[8.1]
  def change
    create_table :swarm_registries do |t|
      t.string :name
      t.string :url
      t.string :username
      t.string :encrypted_password

      t.timestamps
    end
  end
end

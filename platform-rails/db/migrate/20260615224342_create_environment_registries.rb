class CreateEnvironmentRegistries < ActiveRecord::Migration[8.1]
  def change
    create_table :environment_registries do |t|
      t.references :environment, null: false, foreign_key: true
      t.string :url
      t.string :username
      t.string :encrypted_password

      t.timestamps
    end
  end
end

class CreateEnvironmentGroups < ActiveRecord::Migration[8.1]
  def change
    create_table :environment_groups do |t|
      t.string :name
      t.text :description

      t.timestamps
    end
    add_index :environment_groups, :name, unique: true
  end
end

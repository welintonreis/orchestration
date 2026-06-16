class CreateEnvironmentTags < ActiveRecord::Migration[8.1]
  def change
    create_table :environment_tags do |t|
      t.string :name
      t.string :color

      t.timestamps
    end
  end
end

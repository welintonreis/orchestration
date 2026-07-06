class CreateAppTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :app_templates do |t|
      t.string :name, null: false
      t.string :description
      t.string :icon, default: "box"
      t.text :compose_yaml, null: false
      t.json :variables, null: false, default: {}
      t.boolean :built_in, null: false, default: false
      t.timestamps
      t.index :name, unique: true
    end
  end
end

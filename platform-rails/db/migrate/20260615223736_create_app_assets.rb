class CreateAppAssets < ActiveRecord::Migration[8.1]
  def change
    create_table :app_assets do |t|
      t.string :key
      t.string :content_type
      t.binary :data

      t.timestamps
    end
    add_index :app_assets, :key, unique: true
  end
end

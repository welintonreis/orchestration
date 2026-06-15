class CreateAlerts < ActiveRecord::Migration[8.1]
  def change
    create_table :alerts do |t|
      t.string :level, null: false
      t.string :resource, null: false
      t.text :message, null: false
      t.datetime :read_at

      t.timestamps
    end

    add_index :alerts, :level
    add_index :alerts, :read_at
  end
end

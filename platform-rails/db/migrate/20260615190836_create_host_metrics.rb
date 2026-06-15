class CreateHostMetrics < ActiveRecord::Migration[8.1]
  def change
    create_table :host_metrics do |t|
      t.float :cpu_percent, null: false
      t.float :ram_percent, null: false
      t.float :disk_percent, null: false
      t.float :load_1m, null: false
      t.float :load_5m, null: false
      t.float :load_15m, null: false

      t.timestamps
    end

    add_index :host_metrics, :created_at
  end
end

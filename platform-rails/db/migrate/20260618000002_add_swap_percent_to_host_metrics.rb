class AddSwapPercentToHostMetrics < ActiveRecord::Migration[8.1]
  def change
    add_column :host_metrics, :swap_percent, :float, null: false, default: 0
  end
end

class AddEdgeNodeToHostMetrics < ActiveRecord::Migration[8.1]
  def change
    add_reference :host_metrics, :edge_node, null: true, foreign_key: true
  end
end

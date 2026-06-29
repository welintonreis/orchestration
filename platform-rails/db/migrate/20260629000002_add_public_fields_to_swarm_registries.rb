class AddPublicFieldsToSwarmRegistries < ActiveRecord::Migration[8.1]
  def change
    change_table :swarm_registries, bulk: true do |t|
      t.boolean :public,   default: false, null: false
      t.string  :api_type  # docker_hub | quay | generic_v2 | nil
    end
  end
end

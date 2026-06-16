class CreateEnvironmentGroupMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :environment_group_memberships do |t|
      t.references :environment, null: false, foreign_key: true
      t.references :environment_group, null: false, foreign_key: true

      t.timestamps
    end
  end
end

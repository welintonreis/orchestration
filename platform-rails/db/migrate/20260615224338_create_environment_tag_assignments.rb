class CreateEnvironmentTagAssignments < ActiveRecord::Migration[8.1]
  def change
    create_table :environment_tag_assignments do |t|
      t.references :environment, null: false, foreign_key: true
      t.references :environment_tag, null: false, foreign_key: true

      t.timestamps
    end
  end
end

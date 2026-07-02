class CreateTeamEnvironmentPermissions < ActiveRecord::Migration[8.1]
  def change
    create_table :team_environment_permissions do |t|
      t.references :team, null: false, foreign_key: true
      t.references :environment, null: false, foreign_key: true
      t.string :role, null: false, default: "readonly"

      t.timestamps
    end
    add_index :team_environment_permissions, [:team_id, :environment_id], unique: true, name: "index_team_env_perms_on_team_and_env"
  end
end

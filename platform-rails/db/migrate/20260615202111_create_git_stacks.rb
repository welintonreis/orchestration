class CreateGitStacks < ActiveRecord::Migration[8.1]
  def change
    create_table :git_stacks do |t|
      t.string     :name,               null: false
      t.references :environment,        null: false, foreign_key: true
      t.references :git_connection,     null: false, foreign_key: true
      t.string     :compose_file,       default: "docker-compose.yml"
      t.string     :deploy_mode,        default: "swarm_stack"
      t.string     :status,             default: "idle"
      t.text       :last_deploy_output
      t.datetime   :last_deployed_at
      t.string     :webhook_token
      t.boolean    :auto_update,        default: false
      t.integer    :poll_interval,      default: 300

      t.timestamps
    end
  end
end

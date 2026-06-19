class AddGitopsReconcile < ActiveRecord::Migration[8.1]
  def change
    change_table :git_stacks, bulk: true do |t|
      t.string   :sync_status,   default: "unknown"  # synced / out_of_sync / unknown
      t.string   :health,        default: "unknown"  # healthy / progressing / degraded / missing / unknown
      t.boolean  :self_heal,     default: false       # re-apply git state on detected drift
      t.datetime :last_drift_at
      t.text     :drift_detail                         # JSON of last desired-vs-live diff
      t.string   :sync_window                          # e.g. "mon-fri 08:00-20:00" (blank = always)
      t.string   :pre_sync_cmd
      t.string   :post_sync_cmd
    end

    create_table :git_stack_revisions do |t|
      t.references :git_stack, null: false, foreign_key: true
      t.string   :sha
      t.text     :normalized_compose   # last-applied desired state (for three-way diff / rollback)
      t.text     :image_digests        # JSON: service => resolved image@sha256 at deploy time
      t.text     :deploy_output
      t.string   :result, default: "success"  # success / failed
      t.datetime :deployed_at
      t.timestamps
    end
  end
end

class AddTargetGroupToGitStacks < ActiveRecord::Migration[8.1]
  def change
    add_reference :git_stacks, :target_group, null: true, foreign_key: { to_table: :environment_groups }
  end
end

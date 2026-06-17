class AddSourceTypeToGitStacks < ActiveRecord::Migration[8.0]
  def change
    add_column :git_stacks, :source_type, :string, default: "git", null: false
    add_column :git_stacks, :yaml_content, :text
    change_column_null :git_stacks, :git_connection_id, true
  end
end

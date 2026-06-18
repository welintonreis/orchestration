class AddEnvContentToGitStacks < ActiveRecord::Migration[8.1]
  def change
    add_column :git_stacks, :env_content, :text
  end
end

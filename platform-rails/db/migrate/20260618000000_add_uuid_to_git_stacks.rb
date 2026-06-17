class AddUuidToGitStacks < ActiveRecord::Migration[8.1]
  def up
    add_column :git_stacks, :uuid, :string
    GitStack.reset_column_information
    GitStack.find_each { |gs| gs.update_column(:uuid, SecureRandom.uuid) }
    change_column_null :git_stacks, :uuid, false
    add_index :git_stacks, :uuid, unique: true
  end

  def down
    remove_index :git_stacks, :uuid
    remove_column :git_stacks, :uuid
  end
end

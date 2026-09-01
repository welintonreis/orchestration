class AddAvatarToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :avatar_data, :binary
    add_column :users, :avatar_content_type, :string
  end
end

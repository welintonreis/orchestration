class CreateSharedCredentials < ActiveRecord::Migration[8.1]
  def change
    create_table :shared_credentials do |t|
      t.string :name
      t.string :credential_type
      t.string :username
      t.text :encrypted_secret
      t.text :description

      t.timestamps
    end
  end
end

class CreateHudDevices < ActiveRecord::Migration[8.1]
  def change
    create_table :hud_devices do |t|
      t.string   :name,         null: false
      # Só o digest: é credencial Bearer de longa duração numa máquina de
      # terceiro, mesmo tratamento do EdgeNode. Vazou o banco, não vazou acesso.
      t.string   :token_digest, null: false
      t.datetime :revoked_at
      t.datetime :last_seen_at
      t.string   :agent_version

      t.timestamps
    end
    add_index :hud_devices, :token_digest, unique: true
  end
end

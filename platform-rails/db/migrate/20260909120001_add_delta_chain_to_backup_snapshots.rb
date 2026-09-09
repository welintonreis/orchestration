class AddDeltaChainToBackupSnapshots < ActiveRecord::Migration[8.1]
  # A célula DELTAS do HUD precisa saber o tamanho da corrente de deltas desde
  # o último full (restore percorre a corrente inteira: quanto mais longa, mais
  # demorado o restore). Quem sabe isso é o wal-g, e consultá-lo custa um
  # container aws-cli — inaceitável num poll de 15s. Então o job diário, que já
  # tem a lista inteira em mãos, passa a gravar o resumo aqui.
  def change
    add_column :backup_snapshots, :full_count,        :integer
    add_column :backup_snapshots, :delta_count,       :integer
    add_column :backup_snapshots, :deltas_since_full, :integer
    add_column :backup_snapshots, :last_full_at,      :datetime
  end
end

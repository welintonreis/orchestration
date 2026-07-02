class AddKubeMtlsToEnvironments < ActiveRecord::Migration[8.1]
  def change
    change_table :environments, bulk: true do |t|
      t.text :kube_client_cert_ciphertext
      t.text :kube_client_key_ciphertext
    end
  end
end

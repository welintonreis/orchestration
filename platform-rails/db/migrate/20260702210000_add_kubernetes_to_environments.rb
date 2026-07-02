class AddKubernetesToEnvironments < ActiveRecord::Migration[8.1]
  def change
    change_table :environments, bulk: true do |t|
      t.string :kube_api_url
      t.text   :kube_ca_cert
      t.text   :kube_token_ciphertext
    end
  end
end

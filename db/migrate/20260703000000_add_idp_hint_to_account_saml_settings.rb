class AddIdpHintToAccountSamlSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :account_saml_settings, :idp_hint, :string
  end
end

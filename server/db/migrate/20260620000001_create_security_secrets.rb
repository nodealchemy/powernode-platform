# frozen_string_literal: true

# Backing store for the DatabaseBackend of Security::SecretStore — the
# DB-encrypted alternative to Vault. Values are encrypted at rest by Rails
# `encrypts` (AES-GCM, master key); only the (account, scope, key) coordinates
# are in cleartext. One row per logical secret.
class CreateSecuritySecrets < ActiveRecord::Migration[8.0]
  def change
    create_table :security_secrets, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid, index: true
      t.string :scope, null: false
      t.string :key, null: false
      t.text :value # Rails `encrypts` ciphertext
      t.timestamps
    end

    add_index :security_secrets, %i[account_id scope key], unique: true,
              name: "idx_security_secrets_on_account_scope_key"
  end
end

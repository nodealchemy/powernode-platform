# frozen_string_literal: true

# Adds per-account encryption-key path on accounts. The path points to a
# Vault transit key that pepper-encrypts sensitive credentials (provider
# connection access keys, future credential models). The column is nullable
# — accounts get a key on first peppered write, or via an explicit
# Security::AccountEncryptionKeyService.generate_for(account) call.
#
# Reference: comprehensive stabilization sweep P3.
class AddEncryptionKeyVaultPathToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :encryption_key_vault_path, :string
    add_index :accounts, :encryption_key_vault_path,
              unique: true,
              where: "encryption_key_vault_path IS NOT NULL",
              name: "index_accounts_on_encryption_key_vault_path"
  end
end

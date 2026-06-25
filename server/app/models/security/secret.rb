# frozen_string_literal: true

module Security
  # DB-encrypted secret row backing Security::SecretStore's DatabaseBackend.
  # `value` is encrypted at rest by Rails `encrypts` (AES-GCM, master key) — never
  # stored, logged, or exposed in plaintext. Only the (account, scope, key)
  # coordinates are cleartext.
  class Secret < ApplicationRecord
    self.table_name = "security_secrets"

    # Optional: platform-global secrets (e.g. the RS256 JWT signing keypair) are
    # owned by no account (account_id NULL). Account-scoped secrets still set it.
    belongs_to :account, optional: true

    encrypts :value

    validates :scope, presence: true
    # uniqueness scoped by account_id handles NULL correctly at the model layer
    # (one platform-global row per scope/key); a partial unique index enforces it
    # at the DB layer too (Postgres treats NULLs as distinct in the full index).
    validates :key, presence: true, uniqueness: { scope: %i[account_id scope] }
  end
end

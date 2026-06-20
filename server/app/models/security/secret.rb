# frozen_string_literal: true

module Security
  # DB-encrypted secret row backing Security::SecretStore's DatabaseBackend.
  # `value` is encrypted at rest by Rails `encrypts` (AES-GCM, master key) — never
  # stored, logged, or exposed in plaintext. Only the (account, scope, key)
  # coordinates are cleartext.
  class Secret < ApplicationRecord
    self.table_name = "security_secrets"

    belongs_to :account

    encrypts :value

    validates :scope, presence: true
    validates :key, presence: true, uniqueness: { scope: %i[account_id scope] }
  end
end

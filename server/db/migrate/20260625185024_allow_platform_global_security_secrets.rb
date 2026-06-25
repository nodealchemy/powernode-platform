# frozen_string_literal: true

class AllowPlatformGlobalSecuritySecrets < ActiveRecord::Migration[8.1]
  def up
    # Platform-global secrets (e.g. the RS256 JWT signing keypair) are owned by
    # no account. Allow account_id to be NULL and add a PARTIAL unique index so a
    # given (scope, key) is unique among platform-global secrets — the existing
    # (account_id, scope, key) index does NOT enforce this for NULL account_id
    # (Postgres treats NULLs as distinct in a unique index).
    change_column_null :security_secrets, :account_id, true
    add_index :security_secrets, %i[scope key],
              unique: true,
              where: "account_id IS NULL",
              name: "index_security_secrets_platform_global_on_scope_and_key"
  end

  def down
    remove_index :security_secrets,
                 name: "index_security_secrets_platform_global_on_scope_and_key"
    # Irreversible if any platform-global (account_id NULL) rows exist — delete
    # them before rolling back or this raises on the NOT NULL re-add.
    change_column_null :security_secrets, :account_id, false
  end
end

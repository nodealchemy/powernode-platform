# frozen_string_literal: true

# Adds transit_key_version + transit_key_rotated_at columns to accounts.
# Tracks which Vault transit pepper version each account's encryption key
# is currently wrapped with — required so CredentialRestorationService can
# walk accounts that need re-wrapping after a pepper rotation.
#
# Reference: extensions/system/docs/plans/missing-features.md (Vault DR Phase 1).
class AddTransitKeyVersionToAccounts < ActiveRecord::Migration[8.1]
  def change
    change_table :accounts, bulk: true do |t|
      t.string :transit_key_version,
               comment: "Vault transit key version (e.g. 'v1', 'v2') currently wrapping this account's encryption key. Null = pre-rotation backfill needed."
      t.datetime :transit_key_rotated_at,
                 comment: "When the account was last re-wrapped to a new transit key version."
    end

    add_index :accounts, :transit_key_version,
              where: "transit_key_version IS NOT NULL",
              name: "index_accounts_on_transit_key_version"
  end
end

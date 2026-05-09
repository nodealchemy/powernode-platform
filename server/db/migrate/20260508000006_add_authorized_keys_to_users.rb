# frozen_string_literal: true

# Adds a User-level authorized_keys array — operator-supplied OpenSSH-format
# pubkeys that propagate to every node owned by the user's account via
# `System::Node#authorized_keys`.
#
# Closes the `CORE-MIGRATION pending` comment on `System::Node#authorized_keys`
# (server/app/models/system/node.rb) by giving that aggregator a place to
# pull user-bound keys from.
class AddAuthorizedKeysToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :authorized_keys, :jsonb, default: [], null: false
  end
end

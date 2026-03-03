# frozen_string_literal: true

class AddAccountToGitProviders < ActiveRecord::Migration[8.1]
  def up
    add_reference :git_providers, :account, null: true, foreign_key: true, type: :uuid

    # Backfill existing providers — assign to the admin account (first seeded account)
    admin_account = Account.order(:created_at).first
    if admin_account
      execute "UPDATE git_providers SET account_id = '#{admin_account.id}' WHERE account_id IS NULL"
    end

    change_column_null :git_providers, :account_id, false
  end

  def down
    remove_reference :git_providers, :account
  end
end

# frozen_string_literal: true

class AddAccountToPages < ActiveRecord::Migration[8.1]
  def change
    add_reference :pages, :account, type: :uuid, foreign_key: true, null: true

    reversible do |dir|
      dir.up do
        # Backfill: assign all pages to admin account
        execute <<~SQL
          UPDATE pages
          SET account_id = (SELECT id FROM accounts ORDER BY created_at ASC LIMIT 1)
          WHERE account_id IS NULL
        SQL

        # Assign orphaned pages to admin user
        execute <<~SQL
          UPDATE pages
          SET author_id = (SELECT id FROM users ORDER BY created_at ASC LIMIT 1)
          WHERE author_id IS NULL
        SQL

        # Now enforce NOT NULL
        change_column_null :pages, :account_id, false
        change_column_null :pages, :author_id, false
      end
    end
  end
end

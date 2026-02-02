# frozen_string_literal: true

class CreateDelegationPermissions < ActiveRecord::Migration[8.0]
  def change
    create_table :delegation_permissions, id: :string do |t|
      t.references :account_delegation, null: false, foreign_key: true, type: :string
      t.references :permission, null: false, foreign_key: true, type: :string

      t.timestamps
    end

    # Add unique index to prevent duplicate permission assignments
    add_index :delegation_permissions,
              [ :account_delegation_id, :permission_id ],
              unique: true,
              name: 'idx_unique_delegation_permission'
  end
end

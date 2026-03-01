# frozen_string_literal: true

class AddAiSuspendedToAccounts < ActiveRecord::Migration[8.0]
  def change
    add_column :accounts, :ai_suspended, :boolean, default: false, null: false
    add_column :accounts, :ai_suspended_at, :datetime

    add_index :accounts, :ai_suspended, where: "ai_suspended = TRUE"
  end
end

# frozen_string_literal: true

class CreateAiBudgetTransactions < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_budget_transactions, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.references :ai_agent_budget, type: :uuid, null: false, foreign_key: true
      t.references :ai_agent_execution, type: :uuid, foreign_key: true # nullable for manual adjustments
      t.string :transaction_type, null: false # debit, credit, reservation, release, rollover, adjustment
      t.integer :amount_cents, null: false
      t.integer :running_balance_cents, null: false
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :ai_budget_transactions, :transaction_type
    add_index :ai_budget_transactions, :created_at
  end
end

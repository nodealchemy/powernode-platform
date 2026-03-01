# frozen_string_literal: true

class AddCodeFactoryToRalphLoops < ActiveRecord::Migration[8.0]
  def change
    add_reference :ai_ralph_loops, :risk_contract,
      foreign_key: { to_table: :ai_code_factory_risk_contracts }, type: :uuid, null: true
    add_column :ai_ralph_loops, :code_factory_mode, :boolean, default: false
  end
end

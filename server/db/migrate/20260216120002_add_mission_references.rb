# frozen_string_literal: true

class AddMissionReferences < ActiveRecord::Migration[8.0]
  def change
    add_reference :ai_ralph_loops, :mission, type: :uuid, foreign_key: { to_table: :ai_missions }, index: true
    add_reference :ai_runner_dispatches, :mission, type: :uuid, foreign_key: { to_table: :ai_missions }, index: true
    add_reference :ai_code_factory_review_states, :mission, type: :uuid, foreign_key: { to_table: :ai_missions }, index: true
  end
end

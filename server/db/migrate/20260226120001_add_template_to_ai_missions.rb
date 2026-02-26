# frozen_string_literal: true

class AddTemplateToAiMissions < ActiveRecord::Migration[8.0]
  def change
    add_reference :ai_missions, :mission_template, type: :uuid,
                  foreign_key: { to_table: :ai_mission_templates }, index: true
    add_column :ai_missions, :custom_phases, :jsonb
  end
end

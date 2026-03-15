# frozen_string_literal: true

class AddRepeatingToAiRalphTasks < ActiveRecord::Migration[8.0]
  def change
    add_column :ai_ralph_tasks, :repeating, :boolean, default: false, null: false
  end
end

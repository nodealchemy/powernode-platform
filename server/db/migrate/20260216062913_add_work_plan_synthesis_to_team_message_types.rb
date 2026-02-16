# frozen_string_literal: true

class AddWorkPlanSynthesisToTeamMessageTypes < ActiveRecord::Migration[8.1]
  def up
    remove_check_constraint :ai_team_messages, name: "check_team_message_type"
    add_check_constraint :ai_team_messages,
      "message_type IN ('task_assignment', 'task_update', 'task_result', 'work_plan', 'synthesis', 'question', 'answer', 'escalation', 'coordination', 'broadcast', 'human_input')",
      name: "check_team_message_type"
  end

  def down
    remove_check_constraint :ai_team_messages, name: "check_team_message_type"
    add_check_constraint :ai_team_messages,
      "message_type IN ('task_assignment', 'task_update', 'task_result', 'question', 'answer', 'escalation', 'coordination', 'broadcast', 'human_input')",
      name: "check_team_message_type"
  end
end

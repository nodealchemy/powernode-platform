# frozen_string_literal: true

# Adds a structured `metadata` jsonb column to ai_goal_plan_steps.
#
# Why: SkillCompositionRunner records each step's produced outputs to
# `step.metadata["last_outputs"]` and reads them back for (a) rollback hooks
# and (b) cross-step data flow (a successor step pulling a predecessor's
# output as an input). Until now the model had no `metadata` column, so those
# writes were silently dropped for real records — rollback hooks received
# empty outputs and multi-step provisioning missions could not thread data
# between steps. result_summary is a `text` column and stringifies hashes
# lossily, so it is unsuitable as the structured-output store.
class AddMetadataToAiGoalPlanSteps < ActiveRecord::Migration[8.0]
  def change
    add_column :ai_goal_plan_steps, :metadata, :jsonb, default: {}, null: false
  end
end

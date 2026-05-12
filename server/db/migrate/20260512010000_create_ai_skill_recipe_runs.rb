# frozen_string_literal: true

# Audit log for executions of "recipe skills" — skills whose behavior is
# defined by a declarative ordered list of MCP tool invocations stored in
# Ai::Skill.metadata["recipe"], dispatched by Ai::SkillRecipeRunner.
#
# Every recipe execution writes one row here. Step-by-step results are
# captured in steps_log (JSONB array). Operators can replay any past run,
# audit which tools were dispatched with which inputs/outputs, and resume
# paused runs after approval.
#
# This complements Ai::SkillUsageRecord (lightweight outcome tracking) by
# capturing the FULL execution trace — needed for recipes because they
# fan out into multiple tool calls that may need debugging or replay.
class CreateAiSkillRecipeRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_skill_recipe_runs, id: :uuid do |t|
      t.references :account,  type: :uuid, foreign_key: true, null: false
      t.references :ai_skill, type: :uuid, foreign_key: true, null: false, index: false
      t.references :user,     type: :uuid, foreign_key: true, null: true,  index: false
      t.references :ai_agent, type: :uuid, foreign_key: true, null: true,  index: false

      # Execution state
      #
      #   pending              — created but not yet dispatched
      #   running              — actively executing steps
      #   paused_for_approval  — hit a require_approval step; waiting for confirmation
      #   completed            — all steps ran successfully
      #   failed               — a step errored; runner halted
      #   cancelled            — operator aborted before completion
      t.string :status, null: false, default: "pending"

      # User's input variables (matches recipe.inputs schema)
      t.jsonb :inputs, null: false, default: {}

      # Final output bundle (matches recipe.output schema)
      t.jsonb :outputs, null: false, default: {}

      # Per-step trace: ordered array of { id, tool, params, result, started_at, finished_at, error }
      # Used for audit + debugging + replay.
      t.jsonb :steps_log, null: false, default: []

      # When paused for approval, which step ID is waiting
      t.string :pending_step_id

      # If failed, the step that errored + the error message
      t.string :failed_step_id
      t.text   :error_message

      # Whether this run is a dry_run (resolves bindings, doesn't dispatch tools)
      t.boolean :dry_run, null: false, default: false

      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps
    end

    # Operators often query "what runs of skill X happened recently?"
    add_index :ai_skill_recipe_runs, [:ai_skill_id, :created_at]

    # Approval reviewer pulls "paused_for_approval" rows by account
    add_index :ai_skill_recipe_runs, [:account_id, :status]

    # "What did this user run lately?"
    add_index :ai_skill_recipe_runs, [:user_id, :created_at]

    add_index :ai_skill_recipe_runs, :status
  end
end

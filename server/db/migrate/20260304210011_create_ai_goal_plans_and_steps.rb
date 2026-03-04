# frozen_string_literal: true

class CreateAiGoalPlansAndSteps < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_goal_plans, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true, index: true
      t.references :goal, type: :uuid, null: false, foreign_key: { to_table: :ai_agent_goals }
      t.references :ai_agent, type: :uuid, null: false, foreign_key: { to_table: :ai_agents }
      t.references :approved_by, type: :uuid, foreign_key: { to_table: :users }

      t.string :status, null: false, default: "draft"
      t.integer :version, null: false, default: 1
      t.jsonb :plan_data, default: {}
      t.jsonb :validation_result, default: {}
      t.jsonb :risk_assessment, default: {}
      t.decimal :estimated_cost_usd, precision: 10, scale: 4
      t.integer :estimated_duration_minutes
      t.datetime :approved_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :ai_goal_plans, [:goal_id, :version], unique: true, name: "idx_goal_plans_goal_version"
    add_index :ai_goal_plans, [:account_id, :status], name: "idx_goal_plans_account_status"

    create_table :ai_goal_plan_steps, id: :uuid do |t|
      t.references :plan, type: :uuid, null: false, foreign_key: { to_table: :ai_goal_plans }
      t.references :sub_goal, type: :uuid, foreign_key: { to_table: :ai_agent_goals }
      t.references :ralph_task, type: :uuid, foreign_key: { to_table: :ai_ralph_tasks }

      t.integer :step_number, null: false
      t.string :status, null: false, default: "pending"
      t.string :step_type, null: false
      t.string :description
      t.jsonb :dependencies, default: []
      t.jsonb :execution_config, default: {}
      t.decimal :estimated_cost_usd, precision: 10, scale: 4
      t.integer :estimated_duration_minutes
      t.text :result_summary
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :ai_goal_plan_steps, [:plan_id, :step_number], unique: true, name: "idx_goal_plan_steps_order"
    add_index :ai_goal_plan_steps, [:plan_id, :status], name: "idx_goal_plan_steps_status"
  end
end

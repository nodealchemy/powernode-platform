# frozen_string_literal: true

class CreateRalphLoops < ActiveRecord::Migration[8.0]
  def change
    # ===========================================================================
    # Ralph Loops - AI-driven development loop execution system
    # ===========================================================================
    # Ralph loops implement an iterative development pattern:
    # 1. Parse PRD into tasks
    # 2. Execute tasks using AI tools (AMP/Claude Code)
    # 3. Track iterations and learnings
    # 4. Progress through task list until completion
    # ===========================================================================

    create_table :ai_ralph_loops, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid, index: true

      # Basic info
      t.string :name, null: false
      t.text :description

      # Status management (state machine: pending -> running -> paused/completed/failed)
      t.string :status, null: false, default: "pending"

      # PRD and task management (JSONB for flexible task list storage)
      t.jsonb :prd_json, default: {}
      t.text :progress_text

      # Learnings accumulated during execution
      t.jsonb :learnings, default: []

      # Repository configuration
      t.string :repository_url
      t.string :branch, default: "main"

      # Iteration tracking
      t.integer :current_iteration, default: 0
      t.integer :max_iterations, default: 100

      # AI tool configuration (amp or claude_code)
      t.string :ai_tool, null: false, default: "claude_code"

      # Container execution reference (for sandboxed execution)
      t.uuid :container_instance_id

      # Execution timestamps
      t.datetime :started_at
      t.datetime :completed_at

      # Flexible configuration
      t.jsonb :configuration, default: {}

      # Error tracking
      t.text :error_message
      t.string :error_code
      t.jsonb :error_details, default: {}

      # Metrics
      t.integer :total_tasks, default: 0
      t.integer :completed_tasks, default: 0
      t.integer :failed_tasks, default: 0
      t.integer :duration_ms

      t.timestamps
    end

    add_index :ai_ralph_loops, :status
    add_index :ai_ralph_loops, [:account_id, :status]
    add_index :ai_ralph_loops, :ai_tool
    add_index :ai_ralph_loops, :created_at

    add_check_constraint :ai_ralph_loops,
      "status IN ('pending', 'running', 'paused', 'completed', 'failed', 'cancelled')",
      name: "ai_ralph_loops_status_check"

    add_check_constraint :ai_ralph_loops,
      "ai_tool IN ('amp', 'claude_code')",
      name: "ai_ralph_loops_ai_tool_check"

    # ===========================================================================
    # Ralph Tasks - Individual tasks parsed from PRD
    # ===========================================================================

    create_table :ai_ralph_tasks, id: :uuid do |t|
      t.references :ralph_loop, null: false, foreign_key: { to_table: :ai_ralph_loops },
                   type: :uuid, index: true

      # Task identification
      t.string :task_key, null: false
      t.text :description

      # Status tracking
      t.string :status, null: false, default: "pending"

      # Priority and ordering
      t.integer :priority, default: 0
      t.integer :position

      # Dependencies (array of task_key values)
      t.jsonb :dependencies, default: []

      # Acceptance criteria for task completion
      t.text :acceptance_criteria

      # Completion tracking
      t.datetime :iteration_completed_at
      t.integer :completed_in_iteration

      # Error tracking
      t.text :error_message
      t.string :error_code

      # Metadata
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :ai_ralph_tasks, [:ralph_loop_id, :task_key], unique: true
    add_index :ai_ralph_tasks, :status
    add_index :ai_ralph_tasks, :priority

    add_check_constraint :ai_ralph_tasks,
      "status IN ('pending', 'in_progress', 'passed', 'failed', 'blocked', 'skipped')",
      name: "ai_ralph_tasks_status_check"

    # ===========================================================================
    # Ralph Iterations - Each execution iteration of the loop
    # ===========================================================================

    create_table :ai_ralph_iterations, id: :uuid do |t|
      t.references :ralph_loop, null: false, foreign_key: { to_table: :ai_ralph_loops },
                   type: :uuid, index: true
      t.references :ralph_task, foreign_key: { to_table: :ai_ralph_tasks },
                   type: :uuid, index: true

      # Iteration identification
      t.integer :iteration_number, null: false

      # Iteration status
      t.string :status, null: false, default: "pending"

      # AI output and results
      t.text :ai_output
      t.text :ai_prompt
      t.jsonb :ai_response_metadata, default: {}

      # Git integration
      t.string :git_commit_sha
      t.string :git_branch

      # Validation results
      t.boolean :checks_passed
      t.jsonb :check_results, default: {}

      # Timing
      t.integer :duration_ms
      t.datetime :started_at
      t.datetime :completed_at

      # Error tracking
      t.text :error_message
      t.string :error_code
      t.jsonb :error_details, default: {}

      # Learnings extracted from this iteration
      t.text :learning_extracted

      # Token usage
      t.integer :tokens_input, default: 0
      t.integer :tokens_output, default: 0
      t.decimal :cost, precision: 10, scale: 6, default: 0

      t.timestamps
    end

    add_index :ai_ralph_iterations, [:ralph_loop_id, :iteration_number], unique: true
    add_index :ai_ralph_iterations, :status
    add_index :ai_ralph_iterations, :git_commit_sha, where: "git_commit_sha IS NOT NULL"

    add_check_constraint :ai_ralph_iterations,
      "status IN ('pending', 'running', 'completed', 'failed', 'skipped')",
      name: "ai_ralph_iterations_status_check"

    # Add foreign key for container instances if table exists
    add_foreign_key :ai_ralph_loops, :mcp_container_instances,
                    column: :container_instance_id, on_delete: :nullify
  end
end

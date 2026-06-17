# frozen_string_literal: true

# Tier-2(c): first-class revert signal for the improvement loop's ungameable
# metric. A task that was committed but later judged bad is marked reverted.
# Orthogonal to the pass/fail state machine — a reverted task keeps its terminal
# status (history stays truthful) but stops counting as a durable improvement and
# raises its kind's revert_rate. Explicit + operator-driven, never inferred from
# self-reported checks (which the loop deliberately distrusts).
class AddRevertTrackingToAiRalphTasks < ActiveRecord::Migration[8.0]
  def change
    add_column :ai_ralph_tasks, :reverted_at, :datetime
    add_column :ai_ralph_tasks, :revert_reason, :string
    add_index :ai_ralph_tasks, :reverted_at
  end
end

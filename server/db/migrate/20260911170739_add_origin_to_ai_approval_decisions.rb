# frozen_string_literal: true

# MCP identity plan D1, guard (c): every approval decision records the door it
# came through (Ai::ApprovalDecision::ORIGINS). Nullable: rows written before
# this change carry none, and so does a caller that names no door, which a
# request needing a person's own session refuses.
class AddOriginToAiApprovalDecisions < ActiveRecord::Migration[8.1]
  def change
    add_column :ai_approval_decisions, :origin, :string
  end
end

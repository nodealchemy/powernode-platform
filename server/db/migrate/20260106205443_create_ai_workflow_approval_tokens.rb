# frozen_string_literal: true

# Creates AI Workflow approval tokens for secure email-based approval links
# Mirrors the pattern from CI/CD step approval tokens
class CreateAiWorkflowApprovalTokens < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_workflow_approval_tokens, id: :uuid do |t|
      # Reference to the node execution that requires approval
      t.references :ai_workflow_node_execution, type: :uuid, null: false, foreign_key: true

      # Optional reference to user records (for system users)
      t.references :recipient_user, type: :uuid, foreign_key: { to_table: :users }
      t.references :responded_by, type: :uuid, foreign_key: { to_table: :users }

      # Token storage (hashed for security - raw token only available at creation)
      t.string :token_digest, null: false

      # Recipient information
      t.string :recipient_email, null: false

      # Status tracking
      t.string :status, null: false, default: "pending"

      # Response details
      t.text :response_comment

      # Timing
      t.datetime :expires_at, null: false
      t.datetime :responded_at
      t.datetime :email_sent_at

      t.timestamps
    end

    # Unique index on token digest for secure lookups
    add_index :ai_workflow_approval_tokens, :token_digest, unique: true

    # Index for finding tokens by execution and status
    add_index :ai_workflow_approval_tokens, [ :ai_workflow_node_execution_id, :status ],
              name: "idx_ai_workflow_approval_tokens_execution_status"

    # Partial index for finding pending tokens that are expiring
    add_index :ai_workflow_approval_tokens, [ :status, :expires_at ],
              where: "status = 'pending'",
              name: "idx_ai_workflow_approval_tokens_pending_expiry"

    # Constraint to ensure valid status values
    add_check_constraint :ai_workflow_approval_tokens,
                         "status IN ('pending', 'approved', 'rejected', 'expired')",
                         name: "ai_workflow_approval_tokens_status_check"
  end
end

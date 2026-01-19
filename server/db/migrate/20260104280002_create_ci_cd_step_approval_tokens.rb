# frozen_string_literal: true

# Create table for secure approval tokens sent via email
# Allows users to approve/reject steps without logging in
class CreateCiCdStepApprovalTokens < ActiveRecord::Migration[8.0]
  def change
    create_table :ci_cd_step_approval_tokens, id: :uuid do |t|
      t.references :step_execution, type: :uuid, null: false,
                   foreign_key: { to_table: :ci_cd_step_executions }
      t.references :recipient_user, type: :uuid, null: true,
                   foreign_key: { to_table: :users }
      t.references :responded_by, type: :uuid, null: true,
                   foreign_key: { to_table: :users }

      t.string :token_digest, null: false
      t.string :recipient_email, null: false
      t.string :status, null: false, default: "pending"
      t.text :response_comment

      t.datetime :expires_at, null: false
      t.datetime :responded_at
      t.datetime :email_sent_at

      t.timestamps
    end

    # Unique index on token_digest for lookup
    add_index :ci_cd_step_approval_tokens, :token_digest, unique: true

    # Index for finding pending tokens by step execution
    add_index :ci_cd_step_approval_tokens, [:step_execution_id, :status],
              name: "idx_approval_tokens_on_step_execution_and_status"

    # Index for expiry job to find expired tokens
    add_index :ci_cd_step_approval_tokens, [:status, :expires_at],
              name: "idx_approval_tokens_pending_expiry",
              where: "status = 'pending'"

    # Add check constraint for valid statuses
    reversible do |dir|
      dir.up do
        execute <<-SQL
          ALTER TABLE ci_cd_step_approval_tokens
          ADD CONSTRAINT ci_cd_step_approval_tokens_status_check
          CHECK (status IN ('pending', 'approved', 'rejected', 'expired'));
        SQL
      end

      dir.down do
        execute <<-SQL
          ALTER TABLE ci_cd_step_approval_tokens
          DROP CONSTRAINT IF EXISTS ci_cd_step_approval_tokens_status_check;
        SQL
      end
    end
  end
end

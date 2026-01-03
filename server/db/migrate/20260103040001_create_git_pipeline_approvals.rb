# frozen_string_literal: true

class CreateGitPipelineApprovals < ActiveRecord::Migration[8.0]
  def change
    create_table :git_pipeline_approvals, id: :uuid do |t|
      t.references :git_pipeline, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :account, type: :uuid, null: false, foreign_key: { on_delete: :cascade }

      # Request Details
      t.string :gate_name, null: false
      t.string :environment  # e.g., production, staging
      t.text :description

      # State
      t.string :status, null: false, default: "pending"  # pending, approved, rejected, expired, cancelled

      # Users
      t.references :requested_by, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }
      t.references :responded_by, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }

      # Response
      t.text :response_comment
      t.datetime :responded_at
      t.datetime :expires_at

      # Metadata
      t.jsonb :metadata, null: false, default: {}
      t.jsonb :required_approvers, null: false, default: []  # List of user IDs or role names

      t.timestamps
    end

    add_index :git_pipeline_approvals, :status
    add_index :git_pipeline_approvals, :expires_at
    add_index :git_pipeline_approvals, [ :git_pipeline_id, :gate_name ], unique: true
  end
end

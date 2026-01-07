# frozen_string_literal: true

# Add approval configuration to pipeline steps
# Allows steps to require manual approval before execution
class AddApprovalSettingsToCiCdPipelineSteps < ActiveRecord::Migration[8.0]
  def change
    add_column :ci_cd_pipeline_steps, :requires_approval, :boolean, default: false, null: false
    add_column :ci_cd_pipeline_steps, :approval_settings, :jsonb, default: {}, null: false

    # Add comment for documentation
    reversible do |dir|
      dir.up do
        execute <<-SQL
          COMMENT ON COLUMN ci_cd_pipeline_steps.requires_approval IS
            'When true, step execution pauses and sends notifications for manual approval';
          COMMENT ON COLUMN ci_cd_pipeline_steps.approval_settings IS
            'Approval config: {"timeout_hours": 24, "notification_recipients": [], "require_comment": false}';
        SQL
      end
    end
  end
end

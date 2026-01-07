# frozen_string_literal: true

# Add notification configuration to CI/CD pipelines
# Allows configuring who receives notifications and when
class AddNotificationSettingsToCiCdPipelines < ActiveRecord::Migration[8.0]
  def change
    add_column :ci_cd_pipelines, :notification_recipients, :jsonb, default: [], null: false
    add_column :ci_cd_pipelines, :notification_settings, :jsonb, default: {}, null: false

    # Add comment for documentation
    reversible do |dir|
      dir.up do
        execute <<-SQL
          COMMENT ON COLUMN ci_cd_pipelines.notification_recipients IS
            'Array of notification recipients: [{"type": "email"|"user_id", "value": "..."}]';
          COMMENT ON COLUMN ci_cd_pipelines.notification_settings IS
            'Notification preferences: {"on_approval_required": true, "on_completion": false, "on_failure": true}';
        SQL
      end
    end
  end
end

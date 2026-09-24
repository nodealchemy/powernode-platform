# frozen_string_literal: true

# Admin::MaintenanceMode (server/app/services/admin/maintenance_mode.rb) reads
# fresh keys ("maintenance.enabled" etc) rather than reusing the legacy
# "maintenance_mode" AdminSetting key, precisely so this migration is not
# load-bearing for correctness — but a leftover row under the OLD key name is
# still confusing operator-facing debris from two dead writers this feature
# replaced:
#   - Api::V1::AdminSettingsController#update used to write "maintenance_mode"
#     (a value nothing ever read).
#   - Api::V1::Admin::Maintenance::MaintenanceController used to write
#     Rails.application.config.maintenance_mode (in-process only, never an
#     AdminSetting row at all).
# Only the first ever reached the database, so only "maintenance_mode" itself
# is realistically present on any deployment — the sibling keys below
# (maintenance_message/_enabled_at/_estimated_completion/_bypass_ips) were
# never written by any core code path, but are included for completeness in
# case an operator's own tooling poked the generic AdminSetting API directly.
class DeleteLegacyMaintenanceModeAdminSettings < ActiveRecord::Migration[8.0]
  LEGACY_KEYS = %w[
    maintenance_mode
    maintenance_message
    maintenance_enabled_at
    maintenance_estimated_completion
    maintenance_bypass_ips
  ].freeze

  def up
    execute(
      "DELETE FROM admin_settings WHERE key IN (#{LEGACY_KEYS.map { |k| connection.quote(k) }.join(', ')})"
    )
  end

  def down
    # Data-only cleanup of dead rows; nothing to restore.
  end
end

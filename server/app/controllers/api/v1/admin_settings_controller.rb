# frozen_string_literal: true

# Consolidated Admin Settings Controller - Phase 3 Controller Consolidation
#
# This controller manages admin settings and system configuration.
# Delegates business logic to Admin::SettingsService and Admin::SecurityConfigService.
#
# Consolidates:
# - System metrics and overview
# - User and account management
# - Security configuration
# - Payment gateway status
#
class Api::V1::AdminSettingsController < ApplicationController
  include AuditLogging
  include AdminSettings::ExtensionActions
  include AdminSettings::SecurityConfigActions
  include AdminSettings::InfrastructureConfigActions

  before_action -> { require_permission("admin.settings.read") }
  before_action -> { require_permission("admin.settings.update") }, only: %i[update toggle_extension update_development]
  before_action -> { require_permission("admin.account.suspend") }, only: %i[suspend_account activate_account]
  before_action -> { require_permission("admin.settings.security") }, only: %i[update_infrastructure_config update_vault_config]
  # test_vault_connection is a READ, so the class-level admin.settings.read gate
  # covers its connectivity/sealed answer. Naming a `path` turns it into a probe
  # that discloses which KEY NAMES live at an arbitrary Vault KV path — small
  # but real, and it belongs behind the same gate as the other Vault actions.
  # A raise (require_permission) rather than a render, so it HALTS.
  before_action -> { require_permission("admin.settings.security") },
                only: %i[test_vault_connection],
                if: -> { params[:path].present? }

  # =============================================================================
  # OVERVIEW & METRICS
  # =============================================================================

  # GET /api/v1/admin_settings
  def show
    render_success(settings_service.admin_overview)
  end

  # PUT /api/v1/admin_settings
  def update
    settings_params = admin_settings_params
    updated_settings = {}

    settings_params.each do |key, value|
      if value.is_a?(Hash)
        value.each do |sub_key, sub_value|
          setting_key = "#{key}.#{sub_key}"
          AdminSetting.find_or_initialize_by(key: setting_key).update!(value: sub_value.to_s)
          updated_settings[setting_key] = sub_value
        end
      else
        AdminSetting.find_or_initialize_by(key: key.to_s).update!(value: value.to_s)
        updated_settings[key] = value
      end
    end

    update_settings_metadata

    log_audit_event("admin_settings_update", "SystemSettings",
                    metadata: {
                      updated_fields: settings_params.keys,
                      rate_limiting_changed: settings_params.key?(:rate_limiting)
                    })

    render_success(
      message: "Admin settings updated successfully",
      data: updated_settings
    )
  rescue StandardError => e
    Rails.logger.error "Admin settings update failed: #{e.class.name}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    render_error("Admin settings update failed", :unprocessable_content, details: e.message)
  end

  # =============================================================================
  # USER & ACCOUNT MANAGEMENT
  # =============================================================================

  # GET /api/v1/admin_settings/users
  def users
    users_data = settings_service.recent_users_data(limit: 100)
    stats = settings_service.user_management_data

    render_success({
      users: users_data,
      total_count: stats[:total_users],
      active_count: User.where(status: "active").count,
      inactive_count: User.where(status: "inactive").count,
      suspended_count: User.where(status: "suspended").count
    })
  end

  # GET /api/v1/admin_settings/accounts
  def accounts
    accounts_data = settings_service.recent_accounts_data(limit: 100)
    platform_stats = settings_service.platform_statistics

    render_success({
      accounts: accounts_data,
      total_count: platform_stats[:total_accounts],
      active_count: platform_stats[:active_accounts],
      suspended_count: Account.where(status: "suspended").count,
      cancelled_count: Account.where(status: "cancelled").count
    })
  end

  # GET /api/v1/admin_settings/system_logs
  def system_logs
    logs = settings_service.recent_system_logs(limit: 100)

    render_success({
      logs: logs,
      total_count: AuditLog.count
    })
  end

  # POST /api/v1/admin_settings/suspend_account
  def suspend_account
    result = settings_service.suspend_account(
      account_id: params[:account_id],
      reason: params[:reason]
    )

    if result[:success]
      render_success(message: result[:message])
    else
      render_error(result[:error] || result[:errors]&.join(", "), status: :unprocessable_content)
    end
  end

  # POST /api/v1/admin_settings/activate_account
  def activate_account
    result = settings_service.activate_account(
      account_id: params[:account_id],
      reason: params[:reason]
    )

    if result[:success]
      render_success(message: result[:message])
    else
      render_error(result[:error] || result[:errors]&.join(", "), status: :unprocessable_content)
    end
  end

  private

  # =============================================================================
  # SERVICE ACCESSORS
  # =============================================================================

  def settings_service
    @settings_service ||= ::Admin::SettingsService.new(user: current_user)
  end

  # =============================================================================
  # PARAMETER HANDLING
  # =============================================================================

  def admin_settings_params
    params.require(:admin_settings).permit(
      :maintenance_mode,
      :registration_enabled,
      :email_verification_required,
      :require_email_verification,
      :password_complexity_level,
      :session_timeout_minutes,
      :max_failed_login_attempts,
      :account_lockout_duration,
      :system_name,
      :system_email,
      :support_email,
      :platform_url,
      :trial_period_days,
      :payment_retry_attempts,
      :webhook_timeout_seconds,
      :allow_account_deletion,
      :copyright_text,
      system_notifications: {},
      rate_limiting: [
        :enabled,
        :api_requests_per_minute,
        :login_attempts_per_hour,
        :registration_attempts_per_hour,
        :password_reset_attempts_per_hour,
        :email_verification_attempts_per_hour,
        :authenticated_requests_per_hour,
        :impersonation_attempts_per_hour,
        :webhook_requests_per_minute,
        :websocket_connections_per_minute
      ],
      feature_flags: {}
    )
  end

  # =============================================================================
  # HELPERS
  # =============================================================================

  def update_settings_metadata
    metadata = Rails.cache.fetch("system_settings_metadata") || { created_at: Time.current }
    metadata[:updated_at] = Time.current
    Rails.cache.write("system_settings_metadata", metadata, expires_in: 1.year)
  end
end

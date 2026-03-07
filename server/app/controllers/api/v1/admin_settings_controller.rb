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

  before_action -> { require_permission("admin.settings.read") }

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

  # =============================================================================
  # EXTENSIONS MANAGEMENT
  # =============================================================================

  # GET /api/v1/admin_settings/extensions
  def extensions
    extensions_dir = Rails.root.join("..", "extensions")
    extensions = []

    if extensions_dir.directory?
      extensions_dir.children.select(&:directory?).each do |ext_dir|
        meta_file = ext_dir.join("extension.json")
        next unless meta_file.exist?

        begin
          meta = JSON.parse(meta_file.read)
          slug = meta["slug"] || ext_dir.basename.to_s
          extensions << {
            slug: slug,
            name: meta["name"] || slug.titleize,
            description: meta["description"],
            icon: meta["icon"],
            version: meta["version"],
            author: meta["author"],
            homepage: meta["homepage"],
            capabilities: meta["capabilities"] || [],
            installed: extension_installed?(slug),
            enabled: extension_enabled?(slug, meta)
          }
        rescue JSON::ParserError => e
          Rails.logger.warn "Invalid extension.json in #{ext_dir.basename}: #{e.message}"
        end
      end
    end

    render_success(extensions: extensions)
  end

  # PUT /api/v1/admin_settings/extensions/:slug/toggle
  def toggle_extension
    slug = params[:slug]
    extensions_dir = Rails.root.join("..", "extensions", slug)
    meta_file = extensions_dir.join("extension.json")

    unless meta_file.exist?
      return render_error("Extension '#{slug}' not found", :not_found)
    end

    meta = JSON.parse(meta_file.read)
    feature_flag = meta["feature_flag"]

    unless feature_flag.present?
      return render_error("Extension '#{slug}' does not support toggling", :unprocessable_content)
    end

    unless extension_installed?(slug)
      return render_error("Extension '#{slug}' engine is not loaded", :unprocessable_content)
    end

    enabled = ActiveModel::Type::Boolean.new.cast(params[:enabled])

    if defined?(Flipper)
      if enabled
        Flipper.enable(feature_flag.to_sym)
      else
        Flipper.disable(feature_flag.to_sym)
      end
    end

    new_state = extension_enabled?(slug, meta)

    log_audit_event("extension_toggle", "SystemSettings",
                    metadata: { extension: slug, enabled: new_state })

    render_success(
      slug: slug,
      enabled: new_state,
      message: "#{meta['name'] || slug.titleize} #{new_state ? 'enabled' : 'disabled'}"
    )
  rescue JSON::ParserError
    render_error("Invalid extension metadata for '#{slug}'", :unprocessable_content)
  end

  # =============================================================================
  # DEVELOPMENT / ENTERPRISE TOGGLE
  # =============================================================================

  # GET /api/v1/admin_settings/development
  def development
    render_success(Shared::FeatureGateService.development_info)
  end

  # PUT /api/v1/admin_settings/development
  def update_development
    unless Shared::FeatureGateService.enterprise_loaded?
      return render_error("Enterprise engine is not installed", :unprocessable_content)
    end

    enabled = ActiveModel::Type::Boolean.new.cast(params[:enterprise_enabled])
    new_state = Shared::FeatureGateService.set_enterprise_enabled!(enabled)

    log_audit_event("enterprise_mode_toggle", "SystemSettings",
                    metadata: { enterprise_enabled: new_state })

    render_success(
      enterprise_enabled: new_state,
      message: "Enterprise mode #{new_state ? 'enabled' : 'disabled'}"
    )
  end

  # =============================================================================
  # SECURITY CONFIGURATION
  # =============================================================================

  # GET /api/v1/admin_settings/security
  def security_config
    require_permission("admin.settings.security")

    render_success(security_service.get_config)
  rescue StandardError => e
    Rails.logger.error "Security config load failed: #{e.class.name}: #{e.message}"
    render_error("Failed to load security configuration: #{e.message}")
  end

  # PUT /api/v1/admin_settings/security
  def update_security_config
    require_permission("admin.settings.security")

    result = security_service.update_config(security_config_params)

    if result[:success]
      render_success(
        config: result[:config],
        message: result[:message]
      )
    else
      render_error(result[:error], status: :unprocessable_content)
    end
  rescue StandardError => e
    Rails.logger.error "Security config update failed: #{e.class.name}: #{e.message}"
    render_error("Failed to update security configuration: #{e.message}")
  end

  # POST /api/v1/admin_settings/security/test
  def test_security_config
    require_permission("admin.settings.security")

    result = security_service.test_config

    render_success(result)
  end

  # POST /api/v1/admin_settings/security/regenerate_jwt_secret
  def regenerate_jwt_secret
    require_permission("admin.settings.security")

    result = security_service.regenerate_jwt_secret(reason: params[:reason])

    if result[:success]
      render_success(
        message: "JWT secret regenerated successfully",
        new_secret: result[:new_secret],
        grace_period_hours: result[:grace_period_hours],
        grace_period_ends_at: result[:grace_period_ends_at],
        warning: result[:warning],
        instructions: result[:instructions]
      )
    else
      render_error(result[:error], status: :unprocessable_content)
    end
  end

  # DELETE /api/v1/admin_settings/security/blacklisted_tokens
  def clear_blacklisted_tokens
    require_permission("admin.settings.security")

    result = security_service.clear_blacklisted_tokens

    if result[:success]
      render_success(
        cleared_count: result[:cleared_count],
        message: result[:message]
      )
    else
      render_error(result[:error], status: :unprocessable_content)
    end
  end

  # GET /api/v1/admin_settings/security/blacklist_stats
  def blacklist_statistics
    require_permission("admin.settings.security")

    render_success(security_service.blacklist_statistics)
  end

  # GET /api/v1/admin_settings/security/audit_summary
  def security_audit_summary
    require_permission("admin.settings.security")

    days = params[:days]&.to_i || 30
    render_success(security_service.security_audit_summary(days: days))
  end

  # =============================================================================
  # INFRASTRUCTURE CONFIGURATION
  # =============================================================================

  # GET /api/v1/admin_settings/infrastructure
  def infrastructure_config
    config = AdminSetting.redis_config
    # Mask password
    masked_config = config.dup
    masked_config["password"] = "••••••••" if masked_config["password"].present?

    # Get connection status
    connection_status = AdminSetting.test_redis_connection

    render_success(
      redis: masked_config,
      connection: connection_status
    )
  end

  # PUT /api/v1/admin_settings/infrastructure
  def update_infrastructure_config
    redis_params = infrastructure_params

    # Skip password update if masked value sent back
    redis_params.delete("password") if redis_params["password"] == "••••••••"

    AdminSetting.update_redis_config(redis_params)
    Powernode::Redis.reconfigure!

    log_audit_event("infrastructure_config_update", "SystemSettings",
                    metadata: { updated_fields: redis_params.keys })

    # Return updated config with masked password
    config = AdminSetting.redis_config
    config["password"] = "••••••••" if config["password"].present?

    render_success(
      redis: config,
      message: "Infrastructure configuration updated successfully"
    )
  rescue StandardError => e
    Rails.logger.error "Infrastructure config update failed: #{e.class.name}: #{e.message}"
    render_error("Failed to update infrastructure configuration: #{e.message}", :unprocessable_content)
  end

  # POST /api/v1/admin_settings/infrastructure/test_redis
  def test_redis_connection
    # Test with provided config or saved config
    test_config = if params[:redis].present?
      infrastructure_params
    else
      nil
    end

    result = AdminSetting.test_redis_connection(test_config)
    render_success(result)
  end

  private

  # =============================================================================
  # SERVICE ACCESSORS
  # =============================================================================

  def settings_service
    @settings_service ||= ::Admin::SettingsService.new(user: current_user)
  end

  def security_service
    @security_service ||= ::Admin::SecurityConfigService.new(user: current_user)
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

  def infrastructure_params
    params.require(:redis).permit(
      :host, :port, :database, :password, :ssl, :url,
      :connect_timeout, :read_timeout, :write_timeout, :pool_size
    ).to_h
  end

  def security_config_params
    params.require(:security_config).permit(
      csrf: [ :enabled, :token_name, :protection_method, :require_ssl ],
      jwt: [ :access_token_ttl, :refresh_token_ttl, :algorithm, :blacklist_enabled, :require_fresh_tokens_for_sensitive_operations ],
      authentication: [ :max_failed_attempts, :lockout_duration, :require_2fa_for_admin, :session_timeout ],
      api_security: [ :rate_limiting_enabled, :cors_enabled, :require_api_key_for_write_operations, allowed_origins: [] ]
    )
  end

  # =============================================================================
  # HELPERS
  # =============================================================================

  # Check if an extension's engine is loaded in the Rails runtime
  def extension_installed?(slug)
    Shared::FeatureGateService.extension_loaded?(slug)
  end

  # Check if an extension is enabled via its feature flag
  def extension_enabled?(slug, _meta = nil)
    Shared::FeatureGateService.extension_enabled?(slug)
  end

  def update_settings_metadata
    metadata = Rails.cache.fetch("system_settings_metadata") || { created_at: Time.current }
    metadata[:updated_at] = Time.current
    Rails.cache.write("system_settings_metadata", metadata, expires_in: 1.year)
  end
end

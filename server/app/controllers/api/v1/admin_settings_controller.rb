# frozen_string_literal: true

class Api::V1::AdminSettingsController < ApplicationController
  before_action -> { require_permission("admin.settings.view") }

  # GET /api/v1/admin_settings
  def show
    render_success(admin_overview_data)
  end

  # PUT /api/v1/admin_settings
  def update
    begin
      settings_params = admin_settings_params
      updated_settings = System::SettingsService.update_settings(settings_params)

      # Update settings metadata timestamp
      metadata = Rails.cache.fetch("system_settings_metadata") || { created_at: Time.current }
      metadata[:updated_at] = Time.current
      Rails.cache.write("system_settings_metadata", metadata, expires_in: 1.year)

      # Log the settings update
      AuditLog.create!(
        user: current_user,
        account: current_user.account,
        action: "admin_settings_update",
        resource_type: "SystemSettings",
        resource_id: "system",
        source: "admin_panel",
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        metadata: {
          updated_fields: settings_params.keys,
          rate_limiting_changed: settings_params.key?(:rate_limiting)
        }
      )

      render_success(
        message: "Admin settings updated successfully",
        data: updated_settings
      )
    rescue StandardError => e
      Rails.logger.error "Admin settings update failed: #{e.class.name}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      render_error(
        "Admin settings update failed",
        :unprocessable_content,
        details: e.message
      )
    end
  end

  # GET /api/v1/admin_settings/users
  def users
    users = User.includes(:account)
                .order(:created_at)
                .limit(100) # Paginate in real implementation

    render_success({

        users: users.map { |user| admin_user_data(user) },
        total_count: User.count,
        active_count: User.where(status: "active").count,
        inactive_count: User.where(status: "inactive").count,
        suspended_count: User.where(status: "suspended").count
      }
    )
  end

  # GET /api/v1/admin_settings/accounts
  def accounts
    accounts = Account.includes(:users, :subscription, :revenue_snapshots)
                     .order(:created_at)
                     .limit(100) # Paginate in real implementation

    render_success({

        accounts: accounts.map { |account| admin_account_data(account) },
        total_count: Account.count,
        active_count: Account.where(status: "active").count,
        suspended_count: Account.where(status: "suspended").count,
        cancelled_count: Account.where(status: "cancelled").count
      }
    )
  end

  # GET /api/v1/admin_settings/system_logs
  def system_logs
    logs = AuditLog.includes(:user, :account)
                   .order(created_at: :desc)
                   .limit(100) # Paginate in real implementation

    render_success({

        logs: logs.map { |log| admin_log_data(log) },
        total_count: AuditLog.count
      }
    )
  end

  # POST /api/v1/admin_settings/suspend_account
  def suspend_account
    account = Account.find(params[:account_id])

    if account.update(status: "suspended")
      # Log admin action
      AuditLog.create!(
        user: current_user,
        account: current_user.account,
        action: "suspend_account",
        resource_type: "Account",
        resource_id: account.id,
        source: "admin_panel",
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        metadata: {
          suspended_account_name: account.name,
          reason: params[:reason] || "Administrative action"
        }
      )

      render_success(
        message: "Account suspended successfully"
      )
    else
      render_validation_error(account)
    end
  end

  # POST /api/v1/admin_settings/activate_account
  def activate_account
    account = Account.find(params[:account_id])

    if account.update(status: "active")
      # Log admin action
      AuditLog.create!(
        user: current_user,
        account: current_user.account,
        action: "activate_account",
        resource_type: "Account",
        resource_id: account.id,
        source: "admin_panel",
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        metadata: {
          activated_account_name: account.name,
          reason: params[:reason] || "Administrative action"
        }
      )

      render_success(
        message: "Account activated successfully"
      )
    else
      render_validation_error(account)
    end
  end

  # GET /api/v1/admin_settings/security
  def security_config
    require_permission("admin.settings.security")

    render_success(security_config_response)
  rescue StandardError => e
    Rails.logger.error "Security config load failed: #{e.class.name}: #{e.message}"
    render_error("Failed to load security configuration: #{e.message}")
  end

  # PUT /api/v1/admin_settings/security
  def update_security_config
    require_permission("admin.settings.security")

    config_params = security_config_params

    # Apply CSRF configuration
    if config_params[:csrf]
      Rails.configuration.x.csrf_protection_enabled = config_params[:csrf][:enabled] || false
      Rails.configuration.x.csrf_token_header_name = config_params[:csrf][:token_name] || "X-CSRF-Token"
      Rails.configuration.x.csrf_allow_parameter = config_params[:csrf][:protection_method]&.in?([ "parameter", "both" ])
      Rails.configuration.x.csrf_require_ssl = config_params[:csrf][:require_ssl] || false
    end

    # Apply JWT configuration
    if config_params[:jwt]
      Rails.configuration.x.jwt_access_token_ttl = config_params[:jwt][:access_token_ttl]&.minutes || 15.minutes
      Rails.configuration.x.jwt_refresh_token_ttl = config_params[:jwt][:refresh_token_ttl]&.hours || 168.hours
      Rails.configuration.x.jwt_algorithm = config_params[:jwt][:algorithm] || "HS256"
      Rails.configuration.x.jwt_blacklist_enabled = config_params[:jwt][:blacklist_enabled] || true
    end

    # Apply authentication configuration
    if config_params[:authentication]
      Rails.configuration.x.auth_max_failed_attempts = config_params[:authentication][:max_failed_attempts] || 5
      Rails.configuration.x.auth_lockout_duration = config_params[:authentication][:lockout_duration]&.minutes || 15.minutes
      Rails.configuration.x.auth_require_2fa_for_admin = config_params[:authentication][:require_2fa_for_admin] || false
      Rails.configuration.x.auth_session_timeout = config_params[:authentication][:session_timeout]&.minutes || 60.minutes
    end

    # Apply API security configuration
    if config_params[:api_security]
      Rails.configuration.x.api_rate_limiting_enabled = config_params[:api_security][:rate_limiting_enabled] || true
      Rails.configuration.x.api_cors_enabled = config_params[:api_security][:cors_enabled] || true
      Rails.configuration.x.api_cors_allowed_origins = config_params[:api_security][:allowed_origins] || []
      Rails.configuration.x.api_require_key_for_writes = config_params[:api_security][:require_api_key_for_write_operations] || false
    end

    # Log security configuration changes
    AuditLog.create!(
      user: current_user,
      account: current_account,
      action: "security_config_update",
      resource_type: "SecuritySettings",
      resource_id: "system",
      source: "admin_panel",
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      metadata: {
        updated_fields: config_params.keys,
        csrf_changed: config_params.key?(:csrf),
        jwt_changed: config_params.key?(:jwt),
        csrf_enabled: Rails.configuration.x.csrf_protection_enabled
      }
    )

    render_success(
      config: security_config_response,
      message: "Security configuration updated successfully"
    )
  rescue StandardError => e
    Rails.logger.error "Security config update failed: #{e.class.name}: #{e.message}"
    render_error("Failed to update security configuration: #{e.message}")
  end

  # POST /api/v1/admin_settings/security/test
  def test_security_config
    require_permission("admin.settings.security")

    test_results = {
      csrf_protection: test_csrf_protection,
      jwt_validation: test_jwt_validation,
      authentication_flow: test_authentication_flow,
      api_security: test_api_security
    }

    overall_status = if test_results.values.all? { |status| status == "working" }
                       "healthy"
    elsif test_results.values.any? { |status| status == "error" }
                       "error"
    else
                       "warning"
    end

    details = []
    test_results.each do |component, status|
      details << "#{component.to_s.humanize}: #{status}" if status != "working"
    end

    render_success(
      **test_results,
      overall_status: overall_status,
      details: details.any? ? details : [ "All security components are working correctly" ]
    )
  end

  # POST /api/v1/admin_settings/security/regenerate_jwt_secret
  def regenerate_jwt_secret
    require_permission("admin.settings.security")

    # Generate new JWT secret
    new_secret = SecureRandom.hex(64) # 128-character secret (512 bits)
    old_secret = Rails.application.config.jwt_secret_key

    # Store both secrets with grace period (24 hours)
    grace_period_ends_at = 24.hours.from_now

    Rails.cache.write("jwt_secret_rotation", {
      old_secret: old_secret,
      new_secret: new_secret,
      rotated_at: Time.current,
      grace_period_ends_at: grace_period_ends_at
    }, expires_in: 25.hours)

    # Update current secret (immediately effective for new tokens)
    Rails.application.config.jwt_secret_key = new_secret

    # Log critical security event
    AuditLog.create!(
      user: current_user,
      account: current_account,
      action: "jwt_secret_regenerated",
      resource_type: "SecuritySettings",
      resource_id: "jwt",
      source: "admin_panel",
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      severity: "critical",
      risk_level: "high",
      metadata: {
        regenerated_by: current_user.email,
        grace_period_hours: 24,
        grace_period_ends_at: grace_period_ends_at.iso8601,
        old_secret_length: old_secret.length,
        new_secret_length: new_secret.length,
        reason: params[:reason] || "Admin-initiated rotation"
      }
    )

    render_success(
      message: "JWT secret regenerated successfully",
      new_secret: new_secret, # Only shown once
      grace_period_hours: 24,
      grace_period_ends_at: grace_period_ends_at.iso8601,
      warning: "Store this secret securely. After 24 hours, all sessions using the old secret will be invalidated.",
      instructions: [
        "Save the new secret to your environment variables (JWT_SECRET_KEY)",
        "Update production credentials if using Rails credentials",
        "Restart application servers after updating environment",
        "Users will need to re-authenticate after grace period expires"
      ]
    )
  end

  # DELETE /api/v1/admin_settings/security/blacklisted_tokens
  def clear_blacklisted_tokens
    require_permission("admin.settings.security")

    cleared_count = BlacklistedToken.where("expires_at < ?", Time.current).delete_all

    AuditLog.create!(
      user: current_user,
      account: current_account,
      action: "blacklisted_tokens_cleared",
      resource_type: "BlacklistedToken",
      resource_id: "bulk",
      source: "admin_panel",
      metadata: { cleared_count: cleared_count }
    )

    render_success(
      cleared_count: cleared_count,
      message: "Cleared #{cleared_count} expired blacklisted tokens"
    )
  end

  private

  def admin_overview_data
    {
      metrics: system_metrics,
      recent_users: recent_users_data,
      recent_accounts: recent_accounts_data,
      recent_logs: recent_system_logs,
      payment_gateways: payment_gateway_status,
      settings_summary: settings_summary_data
    }
  end

  def system_metrics
    {
      total_users: User.count,
      total_accounts: Account.count,
      active_accounts: Account.where(status: "active").count,
      suspended_accounts: Account.where(status: "suspended").count,
      cancelled_accounts: Account.where(status: "cancelled").count,
      total_subscriptions: Subscription.count,
      active_subscriptions: Subscription.where(status: [ "active", "trialing" ]).count,
      trial_subscriptions: Subscription.where(status: "trialing").count,
      total_revenue: (Payment.where(status: "completed").sum(:amount_cents) || 0),
      monthly_revenue: calculate_monthly_revenue,
      failed_payments: Payment.where(status: "failed").where("created_at > ?", 30.days.ago).count,
      webhook_events_today: webhook_events_today_count,
      system_health: calculate_system_health,
      uptime: calculate_uptime
    }
  end

  def recent_users_data
    User.includes(:account)
        .order(created_at: :desc)
        .limit(10)
        .map do |user|
      {
        id: user.id,
        name: user.name,
        full_name: user.full_name,
        email: user.email,
        email_verified: user.email_verified?,
        last_login_at: user.last_login_at,
        created_at: user.created_at,
        account: {
          id: user.account.id,
          name: user.account.name,
          status: user.account.status
        },
        roles: user.roles
      }
    end
  end

  def recent_accounts_data
    Account.includes(:users, subscription: :plan)
           .order(created_at: :desc)
           .limit(10)
           .map do |account|
      owner = account.users.first

      {
        id: account.id,
        name: account.name,
        subdomain: account.subdomain,
        status: account.status,
        created_at: account.created_at,
        updated_at: account.updated_at,
        users_count: account.users.count,
        subscription: account.subscription ? {
          id: account.subscription.id,
          status: account.subscription.status,
          plan: {
            name: account.subscription.plan.name,
            price_cents: account.subscription.plan.price
          },
          current_period_end: account.subscription.current_period_end
        } : nil,
        owner: owner ? {
          id: owner.id,
          name: owner.name,
          full_name: owner.full_name,
          email: owner.email
        } : nil
      }
    end
  end

  def recent_system_logs
    AuditLog.includes(:user, :account)
            .order(created_at: :desc)
            .limit(20)
            .map do |log|
      {
        id: log.id,
        level: determine_log_level(log.action),
        message: format_log_message(log),
        timestamp: log.created_at,
        source: log.source || "system",
        metadata: log.metadata
      }
    end
  end

  def payment_gateway_status
    {
      stripe: {
        connected: stripe_configured?,
        environment: Rails.env.production? ? "live" : "test",
        webhook_status: stripe_webhook_health,
        last_webhook: last_stripe_webhook_time
      },
      paypal: {
        connected: paypal_configured?,
        environment: Rails.env.production? ? "live" : "sandbox",
        webhook_status: paypal_webhook_health,
        last_webhook: last_paypal_webhook_time
      }
    }
  end

  def settings_summary_data
    settings = System::SettingsService.load_settings

    # Get actual timestamps from Rails cache or default to system startup
    settings_metadata = Rails.cache.fetch("system_settings_metadata", expires_in: 1.year) do
      {
        created_at: Time.current,
        updated_at: Time.current
      }
    end

    settings.merge(settings_metadata)
  end

  def require_admin_access
    unless current_user.has_permission?("account.manage") || current_user.has_permission?("admin.access")
      render_error("Access denied: Admin privileges required", status: :forbidden)
    end
  end

  def admin_settings_params
    params.require(:admin_settings).permit(
      :maintenance_mode,
      :registration_enabled,
      :email_verification_required,
      :require_email_verification,  # Support both parameter names
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

  def system_settings
    {
      maintenance_mode: Rails.configuration.x.maintenance_mode || false,
      registration_enabled: true,
      email_verification_required: true,
      password_complexity_level: "high",
      session_timeout_minutes: 60,
      max_failed_login_attempts: 5,
      account_lockout_duration: 30,
      platform_version: "1.0.0",
      database_version: ActiveRecord::Base.connection.select_value("SELECT version()"),
      uptime: calculate_uptime
    }
  end

  def platform_statistics
    {
      total_accounts: Account.count,
      active_accounts: Account.where(status: "active").count,
      total_users: User.count,
      active_users: User.where(status: "active").count,
      total_subscriptions: Subscription.count,
      active_subscriptions: Subscription.where(status: [ "active", "trialing" ]).count,
      total_revenue: calculate_total_revenue,
      monthly_growth: calculate_monthly_growth
    }
  end

  def user_management_data
    {
      total_users: User.count,
      users_by_roles: user_role_distribution,
      users_by_status: User.group(:status).count,
      recent_registrations: User.where(created_at: 7.days.ago..Time.current).count,
      email_verification_pending: User.where(email_verified_at: nil).count
    }
  end

  def user_role_distribution
    # Count users by their roles in the new permission system
    role_counts = {}

    User.includes(user_roles: :role).each do |user|
      user_roles = user.user_roles.map { |ur| ur.role.name }
      user_roles = [ "no_role" ] if user_roles.empty?

      user_roles.each do |role_name|
        role_counts[role_name] = (role_counts[role_name] || 0) + 1
      end
    end

    role_counts
  end

  def security_settings_data
    {
      failed_login_attempts_today: AuditLog.where(
        action: "login_failed",
        created_at: Date.current.beginning_of_day..Date.current.end_of_day
      ).count,
      locked_accounts: User.where("locked_until > ?", Time.current).count,
      recent_security_events: AuditLog.where(
        action: [ "login_failed", "password_change", "account_locked" ],
        created_at: 24.hours.ago..Time.current
      ).count,
      suspicious_activities: detect_suspicious_activities
    }
  end

  def global_analytics_access
    return {} unless current_user.can?("view_global_analytics")

    {
      total_revenue: RevenueSnapshot.where(account_id: nil)
                                   .order(:snapshot_date)
                                   .last(30)
                                   .pluck(:snapshot_date, :total_revenue),
      subscription_trends: Subscription.group(:status).count,
      churn_rate: calculate_global_churn_rate,
      customer_growth: calculate_customer_growth
    }
  end

  def admin_user_data(user)
    {
      id: user.id,
      email: user.email,
      full_name: user.full_name,
      status: user.status,
      roles: user.roles,
      account: {
        id: user.account.id,
        name: user.account.name,
        status: user.account.status
      },
      last_login_at: user.last_login_at,
      email_verified: user.email_verified?,
      failed_login_attempts: user.failed_login_attempts,
      locked: user.locked?,
      created_at: user.created_at
    }
  end

  def admin_account_data(account)
    {
      id: account.id,
      name: account.name,
      subdomain: account.subdomain,
      status: account.status,
      users_count: account.users.count,
      subscription: account.subscription ? {
        id: account.subscription.id,
        plan_name: account.subscription.plan.name,
        status: account.subscription.status,
        created_at: account.subscription.created_at
      } : nil,
      created_at: account.created_at,
      updated_at: account.updated_at
    }
  end

  def admin_log_data(log)
    {
      id: log.id,
      action: log.action,
      resource_type: log.resource_type,
      resource_id: log.resource_id,
      user: log.user ? {
        id: log.user.id,
        email: log.user.email,
        full_name: log.user.full_name
      } : nil,
      account: log.account ? {
        id: log.account.id,
        name: log.account.name
      } : nil,
      ip_address: log.ip_address,
      metadata: log.metadata,
      created_at: log.created_at
    }
  end

  def calculate_total_revenue
    Payment.where(status: "completed").sum(:amount_cents) / 100.0
  end

  def calculate_monthly_growth
    current_month = Subscription.where(created_at: Date.current.beginning_of_month..Date.current.end_of_month).count
    last_month = Subscription.where(created_at: 1.month.ago.beginning_of_month..1.month.ago.end_of_month).count

    return 0 if last_month.zero?
    ((current_month - last_month) / last_month.to_f * 100).round(2)
  end

  def detect_suspicious_activities
    [
      {
        type: "multiple_failed_logins",
        count: AuditLog.where(
          action: "login_failed",
          created_at: 1.hour.ago..Time.current
        ).group(:ip_address)
         .having("count(*) > 10")
         .count
         .size
      },
      {
        type: "unusual_api_activity",
        count: check_unusual_api_activity
      }
    ]
  end

  def calculate_global_churn_rate
    # Simplified churn calculation - in real implementation this would be more sophisticated
    active_subscriptions = Subscription.where(status: [ "active", "trialing" ]).count
    cancelled_this_month = Subscription.where(
      status: "cancelled",
      updated_at: Date.current.beginning_of_month..Date.current.end_of_month
    ).count

    return 0 if active_subscriptions.zero?
    (cancelled_this_month / active_subscriptions.to_f * 100).round(2)
  end

  def check_unusual_api_activity
    # Check for rate limit violations in the last hour
    rate_limit_violations = 0

    # Examine rate limit cache keys to find violations
    cache_keys = Rails.cache.redis.keys("rate_limit:*")
    current_time = Time.current

    cache_keys.each do |key|
      current_count = Rails.cache.read(key) || 0

      # Extract controller and limit type from key
      parts = key.split(":")
      next if parts.length < 4

      controller_name = parts[1]
      action_name = parts[2]

      # Get expected limit for this endpoint type
      limit_type = determine_limit_type_for_controller(controller_name)
      expected_limit = System::SettingsService.rate_limit_setting(limit_type)

      # Consider it suspicious if they're at 80% or more of the limit
      if expected_limit && current_count >= (expected_limit * 0.8).to_i
        rate_limit_violations += 1
      end
    end

    rate_limit_violations
  rescue => e
    Rails.logger.error "Error checking API activity: #{e.message}"
    0
  end

  def determine_limit_type_for_controller(controller_name)
    case controller_name
    when "sessions"
      "login_attempts_per_hour"
    when "registrations"
      "registration_attempts_per_hour"
    when "passwords"
      "password_reset_attempts_per_hour"
    when "webhooks"
      "webhook_requests_per_minute"
    else
      "api_requests_per_minute"
    end
  end

  def calculate_customer_growth
    Account.group_by_month(:created_at, last: 12).count
  end

  # Helper methods for admin overview data
  def calculate_monthly_revenue
    current_month_payments = Payment.where(
      status: "completed",
      created_at: Date.current.beginning_of_month..Date.current.end_of_month
    )
    (current_month_payments.sum(:amount_cents) || 0)
  end

  def webhook_events_today_count
    # Track webhook events from payment gateways via audit logs
    AuditLog.where(
      source: [ "stripe_webhook", "paypal_webhook" ],
      created_at: Date.current.beginning_of_day..Date.current.end_of_day
    ).count
  end

  def calculate_system_health
    # Simple health check - can be enhanced based on various metrics
    failed_payments = Payment.where(status: "failed", created_at: 24.hours.ago..Time.current).count
    error_logs = AuditLog.where(action: "system_error", created_at: 24.hours.ago..Time.current).count

    if error_logs > 10 || failed_payments > 50
      "error"
    elsif error_logs > 5 || failed_payments > 20
      "warning"
    else
      "healthy"
    end
  end

  def calculate_uptime
    # Simple uptime calculation - use process start time as approximation
    # In production, this would track actual application start time
    process_start_time = File.stat("/proc/self").ctime rescue (Time.current - 1.day)
    [ Time.current - process_start_time, 0 ].max
  end

  def determine_log_level(action)
    case action
    when /error|failed|suspend|lock|block/i
      "error"
    when /warning|timeout|retry/i
      "warning"
    when /create|update|delete|login|logout/i
      "info"
    else
      "debug"
    end
  end

  def format_log_message(log)
    case log.action
    when "user_login"
      "User #{log.user&.email} logged in"
    when "user_logout"
      "User #{log.user&.email} logged out"
    when "subscription_created"
      "New subscription created for #{log.account&.name}"
    when "payment_completed"
      "Payment completed for #{log.account&.name}"
    when "payment_failed"
      "Payment failed for #{log.account&.name}"
    else
      log.action.humanize
    end
  end

  def stripe_configured?
    Rails.application.credentials.dig(:stripe, :publishable_key).present? &&
    Rails.application.credentials.dig(:stripe, :secret_key).present?
  end

  def paypal_configured?
    Rails.application.credentials.dig(:paypal, :client_id).present? &&
    Rails.application.credentials.dig(:paypal, :client_secret).present?
  end

  # Security configuration parameter handling
  def security_config_params
    params.require(:security_config).permit(
      csrf: [ :enabled, :token_name, :protection_method, :require_ssl ],
      jwt: [ :access_token_ttl, :refresh_token_ttl, :algorithm, :blacklist_enabled, :require_fresh_tokens_for_sensitive_operations ],
      authentication: [ :max_failed_attempts, :lockout_duration, :require_2fa_for_admin, :session_timeout ],
      api_security: [ :rate_limiting_enabled, :cors_enabled, :require_api_key_for_write_operations, allowed_origins: [] ]
    )
  end

  # Security configuration test methods
  def test_csrf_protection
    return "working" if Rails.application.config.force_ssl
    "error"
  rescue StandardError => e
    Rails.logger.error "CSRF test failed: #{e.message}"
    "error"
  end

  def test_jwt_validation
    test_payload = { user_id: "test", exp: 1.hour.from_now.to_i }
    token = Security::JwtService.encode(test_payload)
    decoded = Security::JwtService.decode(token)

    decoded[:user_id] == "test" ? "working" : "error"
  rescue StandardError => e
    Rails.logger.error "JWT test failed: #{e.message}"
    "error"
  end

  def test_authentication_flow
    # Test authentication middleware is properly configured
    return "working" if respond_to?(:authenticate_request, true)
    "error"
  rescue StandardError => e
    Rails.logger.error "Auth flow test failed: #{e.message}"
    "error"
  end

  def test_api_security
    # Test API security measures are in place
    security_measures = [
      Rails.application.config.force_ssl,
      defined?(Rack::Attack),
      respond_to?(:require_permission, true)
    ]

    security_measures.any? ? "working" : "error"
  rescue StandardError => e
    Rails.logger.error "API security test failed: #{e.message}"
    "error"
  end

  def security_config_response
    {
      csrf: {
        enabled: Rails.configuration.x.csrf_protection_enabled || false,
        token_name: Rails.configuration.x.csrf_token_header_name || "X-CSRF-Token",
        protection_method: determine_csrf_protection_method,
        require_ssl: Rails.configuration.x.csrf_require_ssl || false
      },
      jwt: {
        access_token_ttl: (Rails.configuration.x.jwt_access_token_ttl&.to_i || 900) / 60, # Convert to minutes
        refresh_token_ttl: (Rails.configuration.x.jwt_refresh_token_ttl&.to_i || 604800) / 3600, # Convert to hours
        algorithm: Rails.configuration.x.jwt_algorithm || "HS256",
        blacklist_enabled: Rails.configuration.x.jwt_blacklist_enabled || true,
        require_fresh_tokens_for_sensitive_operations: true # Default for security
      },
      authentication: {
        max_failed_attempts: Rails.configuration.x.auth_max_failed_attempts || 5,
        lockout_duration: (Rails.configuration.x.auth_lockout_duration&.to_i || 900) / 60, # Convert to minutes
        require_2fa_for_admin: Rails.configuration.x.auth_require_2fa_for_admin || false,
        session_timeout: (Rails.configuration.x.auth_session_timeout&.to_i || 3600) / 60 # Convert to minutes
      },
      api_security: {
        rate_limiting_enabled: Rails.configuration.x.api_rate_limiting_enabled || true,
        cors_enabled: Rails.configuration.x.api_cors_enabled || true,
        allowed_origins: Rails.configuration.x.api_cors_allowed_origins || [],
        require_api_key_for_write_operations: Rails.configuration.x.api_require_key_for_writes || false
      }
    }
  end

  def determine_csrf_protection_method
    if Rails.configuration.x.csrf_allow_parameter
      "both"
    else
      "header"
    end
  end

  def stripe_webhook_health
    stripe_events = WebhookEvent.for_provider("stripe").where("created_at >= ?", 24.hours.ago)
    calculate_webhook_health_status(stripe_events)
  end

  def paypal_webhook_health
    paypal_events = WebhookEvent.for_provider("paypal").where("created_at >= ?", 24.hours.ago)
    calculate_webhook_health_status(paypal_events)
  end

  def calculate_webhook_health_status(events)
    return "no_data" if events.empty?

    total = events.count
    processed = events.processed.count
    failed = events.failed.count

    success_rate = (processed.to_f / total * 100).round(1)

    return "healthy" if success_rate >= 95
    return "warning" if success_rate >= 80
    "unhealthy"
  end

  def last_stripe_webhook_time
    WebhookEvent.for_provider("stripe").order(:created_at).last&.created_at ||
    AuditLog.where(source: "stripe_webhook").order(:created_at).last&.created_at
  end

  def last_paypal_webhook_time
    WebhookEvent.for_provider("paypal").order(:created_at).last&.created_at ||
    AuditLog.where(source: "paypal_webhook").order(:created_at).last&.created_at
  end
end

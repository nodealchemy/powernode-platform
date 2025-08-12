# frozen_string_literal: true

class Api::V1::AdminSettingsController < ApplicationController
  before_action :require_admin_access

  # GET /api/v1/admin_settings
  def show
    render json: admin_overview_data, status: :ok
  end

  # PUT /api/v1/admin_settings
  def update
    begin
      settings_params = admin_settings_params
      updated_settings = SystemSettingsService.update_settings(settings_params)
      
      # Log the settings update
      AuditLog.create!(
        user: current_user,
        account: current_user.account,
        action: 'admin_settings_update',
        resource_type: 'SystemSettings',
        resource_id: 'system',
        source: 'admin_panel',
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        metadata: {
          updated_fields: settings_params.keys,
          rate_limiting_changed: settings_params.key?(:rate_limiting)
        }
      )

      render json: {
        success: true,
        data: updated_settings,
        message: "Admin settings updated successfully"
      }, status: :ok
    rescue StandardError => e
      Rails.logger.error "Admin settings update failed: #{e.class.name}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      render json: {
        success: false,
        error: "Admin settings update failed",
        details: e.message
      }, status: :unprocessable_content
    end
  end

  # GET /api/v1/admin_settings/users
  def users
    users = User.includes(:account)
                .order(:created_at)
                .limit(100) # Paginate in real implementation

    render json: {
      success: true,
      data: {
        users: users.map { |user| admin_user_data(user) },
        total_count: User.count,
        active_count: User.where(status: 'active').count,
        inactive_count: User.where(status: 'inactive').count,
        suspended_count: User.where(status: 'suspended').count
      }
    }, status: :ok
  end

  # GET /api/v1/admin_settings/accounts
  def accounts
    accounts = Account.includes(:users, :subscription, :revenue_snapshots)
                     .order(:created_at)
                     .limit(100) # Paginate in real implementation

    render json: {
      success: true,
      data: {
        accounts: accounts.map { |account| admin_account_data(account) },
        total_count: Account.count,
        active_count: Account.where(status: 'active').count,
        suspended_count: Account.where(status: 'suspended').count,
        cancelled_count: Account.where(status: 'cancelled').count
      }
    }, status: :ok
  end

  # GET /api/v1/admin_settings/system_logs
  def system_logs
    logs = AuditLog.includes(:user, :account)
                   .order(created_at: :desc)
                   .limit(100) # Paginate in real implementation

    render json: {
      success: true,
      data: {
        logs: logs.map { |log| admin_log_data(log) },
        total_count: AuditLog.count
      }
    }, status: :ok
  end

  # POST /api/v1/admin_settings/suspend_account
  def suspend_account
    account = Account.find(params[:account_id])
    
    if account.update(status: 'suspended')
      # Log admin action
      AuditLog.create!(
        user: current_user,
        account: current_user.account,
        action: 'suspend_account',
        resource_type: 'Account',
        resource_id: account.id,
        source: 'admin_panel',
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        metadata: { 
          suspended_account_name: account.name,
          reason: params[:reason] || 'Administrative action'
        }
      )

      render json: {
        success: true,
        message: "Account suspended successfully"
      }, status: :ok
    else
      render json: {
        success: false,
        error: "Failed to suspend account",
        details: account.errors.full_messages
      }, status: :unprocessable_content
    end
  end

  # POST /api/v1/admin_settings/activate_account
  def activate_account
    account = Account.find(params[:account_id])
    
    if account.update(status: 'active')
      # Log admin action
      AuditLog.create!(
        user: current_user,
        account: current_user.account,
        action: 'activate_account',
        resource_type: 'Account',
        resource_id: account.id,
        source: 'admin_panel',
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        metadata: { 
          activated_account_name: account.name,
          reason: params[:reason] || 'Administrative action'
        }
      )

      render json: {
        success: true,
        message: "Account activated successfully"
      }, status: :ok
    else
      render json: {
        success: false,
        error: "Failed to activate account",
        details: account.errors.full_messages
      }, status: :unprocessable_content
    end
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
      active_accounts: Account.where(status: 'active').count,
      suspended_accounts: Account.where(status: 'suspended').count,
      cancelled_accounts: Account.where(status: 'cancelled').count,
      total_subscriptions: Subscription.count,
      active_subscriptions: Subscription.where(status: ['active', 'trialing']).count,
      trial_subscriptions: Subscription.where(status: 'trialing').count,
      total_revenue: (Payment.where(status: 'completed').sum(:amount_cents) || 0),
      monthly_revenue: calculate_monthly_revenue,
      failed_payments: Payment.where(status: 'failed').where('created_at > ?', 30.days.ago).count,
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
        first_name: user.first_name,
        last_name: user.last_name,
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
        role: user.role
      }
    end
  end

  def recent_accounts_data
    Account.includes(:users, subscription: :plan)
           .order(created_at: :desc)
           .limit(10)
           .map do |account|
      owner = account.users.where(role: 'owner').first || account.users.first
      
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
          first_name: owner.first_name,
          last_name: owner.last_name,
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
        source: log.source || 'system',
        metadata: log.metadata
      }
    end
  end

  def payment_gateway_status
    {
      stripe: {
        connected: stripe_configured?,
        environment: Rails.env.production? ? 'live' : 'test',
        webhook_status: stripe_webhook_health,
        last_webhook: last_stripe_webhook_time
      },
      paypal: {
        connected: paypal_configured?,
        environment: Rails.env.production? ? 'live' : 'sandbox',
        webhook_status: paypal_webhook_health,
        last_webhook: last_paypal_webhook_time
      }
    }
  end

  def settings_summary_data
    SystemSettingsService.load_settings.merge({
      created_at: 30.days.ago, # TODO: Store actual settings creation time
      updated_at: 1.day.ago     # TODO: Store actual settings update time
    })
  end

  def require_admin_access
    unless current_user.owner? || current_user.admin?
      render json: {
        success: false,
        error: "Access denied: Admin privileges required"
      }, status: :forbidden
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
        :webhook_requests_per_minute
      ],
      feature_flags: {}
    )
  end

  def system_settings
    {
      maintenance_mode: false, # TODO: Implement maintenance mode
      registration_enabled: true,
      email_verification_required: true,
      password_complexity_level: 'high',
      session_timeout_minutes: 60,
      max_failed_login_attempts: 5,
      account_lockout_duration: 30,
      platform_version: '1.0.0',
      database_version: ActiveRecord::Base.connection.select_value('SELECT version()'),
      uptime: calculate_uptime
    }
  end

  def platform_statistics
    {
      total_accounts: Account.count,
      active_accounts: Account.where(status: 'active').count,
      total_users: User.count,
      active_users: User.where(status: 'active').count,
      total_subscriptions: Subscription.count,
      active_subscriptions: Subscription.where(status: ['active', 'trialing']).count,
      total_revenue: calculate_total_revenue,
      monthly_growth: calculate_monthly_growth
    }
  end

  def user_management_data
    {
      total_users: User.count,
      users_by_role: User.group(:role).count,
      users_by_status: User.group(:status).count,
      recent_registrations: User.where(created_at: 7.days.ago..Time.current).count,
      email_verification_pending: User.where(email_verified_at: nil).count
    }
  end

  def security_settings_data
    {
      failed_login_attempts_today: AuditLog.where(
        action: 'login_failed',
        created_at: Date.current.beginning_of_day..Date.current.end_of_day
      ).count,
      locked_accounts: User.where('locked_until > ?', Time.current).count,
      recent_security_events: AuditLog.where(
        action: ['login_failed', 'password_change', 'account_locked'],
        created_at: 24.hours.ago..Time.current
      ).count,
      suspicious_activities: detect_suspicious_activities
    }
  end

  def global_analytics_access
    return {} unless current_user.can?('view_global_analytics')

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
      role: user.role,
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
    Payment.where(status: 'completed').sum(:amount_cents) / 100.0
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
        type: 'multiple_failed_logins',
        count: AuditLog.where(
          action: 'login_failed',
          created_at: 1.hour.ago..Time.current
        ).group(:ip_address)
         .having('count(*) > 10')
         .count
         .size
      },
      {
        type: 'unusual_api_activity',
        count: 0 # TODO: Implement API rate monitoring
      }
    ]
  end

  def calculate_global_churn_rate
    # Simplified churn calculation - in real implementation this would be more sophisticated
    active_subscriptions = Subscription.where(status: ['active', 'trialing']).count
    cancelled_this_month = Subscription.where(
      status: 'cancelled',
      updated_at: Date.current.beginning_of_month..Date.current.end_of_month
    ).count

    return 0 if active_subscriptions.zero?
    (cancelled_this_month / active_subscriptions.to_f * 100).round(2)
  end

  def calculate_customer_growth
    Account.group_by_month(:created_at, last: 12).count
  end

  # Helper methods for admin overview data
  def calculate_monthly_revenue
    current_month_payments = Payment.where(
      status: 'completed',
      created_at: Date.current.beginning_of_month..Date.current.end_of_month
    )
    (current_month_payments.sum(:amount_cents) || 0)
  end

  def webhook_events_today_count
    # TODO: Implement webhook event tracking
    AuditLog.where(
      source: ['stripe_webhook', 'paypal_webhook'],
      created_at: Date.current.beginning_of_day..Date.current.end_of_day
    ).count
  end

  def calculate_system_health
    # Simple health check - can be enhanced based on various metrics
    failed_payments = Payment.where(status: 'failed', created_at: 24.hours.ago..Time.current).count
    error_logs = AuditLog.where(action: 'system_error', created_at: 24.hours.ago..Time.current).count
    
    if error_logs > 10 || failed_payments > 50
      'error'
    elsif error_logs > 5 || failed_payments > 20
      'warning'
    else
      'healthy'
    end
  end

  def calculate_uptime
    # Simple uptime calculation - use process start time as approximation
    # In production, this would track actual application start time
    process_start_time = File.stat('/proc/self').ctime rescue (Time.current - 1.day)
    [Time.current - process_start_time, 0].max
  end

  def determine_log_level(action)
    case action
    when /error|failed|suspend|lock|block/i
      'error'
    when /warning|timeout|retry/i
      'warning'
    when /create|update|delete|login|logout/i
      'info'
    else
      'debug'
    end
  end

  def format_log_message(log)
    case log.action
    when 'user_login'
      "User #{log.user&.email} logged in"
    when 'user_logout'
      "User #{log.user&.email} logged out"
    when 'subscription_created'
      "New subscription created for #{log.account&.name}"
    when 'payment_completed'
      "Payment completed for #{log.account&.name}"
    when 'payment_failed'
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

  def stripe_webhook_health
    stripe_events = WebhookEvent.for_provider('stripe').where('created_at >= ?', 24.hours.ago)
    calculate_webhook_health_status(stripe_events)
  end

  def paypal_webhook_health
    paypal_events = WebhookEvent.for_provider('paypal').where('created_at >= ?', 24.hours.ago)
    calculate_webhook_health_status(paypal_events)
  end

  def calculate_webhook_health_status(events)
    return 'no_data' if events.empty?
    
    total = events.count
    processed = events.processed.count
    failed = events.failed.count
    
    success_rate = (processed.to_f / total * 100).round(1)
    
    return 'healthy' if success_rate >= 95
    return 'warning' if success_rate >= 80
    'unhealthy'
  end

  def last_stripe_webhook_time
    WebhookEvent.for_provider('stripe').order(:created_at).last&.created_at ||
    AuditLog.where(source: 'stripe_webhook').order(:created_at).last&.created_at
  end

  def last_paypal_webhook_time
    WebhookEvent.for_provider('paypal').order(:created_at).last&.created_at ||
    AuditLog.where(source: 'paypal_webhook').order(:created_at).last&.created_at
  end
end
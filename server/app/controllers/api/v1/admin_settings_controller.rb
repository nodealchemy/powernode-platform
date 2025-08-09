# frozen_string_literal: true

class Api::V1::AdminSettingsController < ApplicationController
  before_action :require_admin_access

  # GET /api/v1/admin_settings
  def show
    render json: {
      success: true,
      data: {
        system_settings: system_settings,
        platform_stats: platform_statistics,
        user_management: user_management_data,
        security_settings: security_settings_data,
        global_analytics: global_analytics_access
      }
    }, status: :ok
  end

  # PUT /api/v1/admin_settings
  def update
    result = AdminSettingsUpdateService.new(
      user: current_user,
      params: admin_settings_params
    ).call

    if result[:success]
      render json: {
        success: true,
        data: result[:data],
        message: "Admin settings updated successfully"
      }, status: :ok
    else
      render json: {
        success: false,
        error: "Admin settings update failed",
        details: result[:errors]
      }, status: :unprocessable_content
    end
  end

  # GET /api/v1/admin_settings/users
  def users
    users = User.includes(:account, :roles)
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
      :password_complexity_level,
      :session_timeout_minutes,
      :max_failed_login_attempts,
      :account_lockout_duration,
      system_notifications: {},
      rate_limiting: {},
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
      uptime: Time.current - Rails.application.config.startup_time rescue 'Unknown'
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
      users_by_role: User.joins(:roles)
                         .group('roles.name')
                         .count,
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
      roles: user.roles.pluck(:name),
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
end
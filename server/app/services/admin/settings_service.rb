# frozen_string_literal: true

module Admin
  # Service for managing admin settings and system configuration
  #
  # Provides settings management including:
  # - System metrics and overview
  # - User and account management data
  # - System logs retrieval
  # - Account status management
  # - Payment gateway status
  # - Platform statistics
  #
  # Usage:
  #   service = Admin::SettingsService.new(user: current_user)
  #   overview = service.admin_overview
  #
  class SettingsService
    attr_reader :user, :account

    def initialize(user:)
      @user = user
      @account = user.account
    end

    # Get complete admin overview data
    # @return [Hash] Admin overview with all sections
    def admin_overview
      {
        metrics: system_metrics,
        recent_users: recent_users_data,
        recent_accounts: recent_accounts_data,
        recent_logs: recent_system_logs,
        payment_gateways: payment_gateway_status,
        settings_summary: settings_summary_data
      }
    end

    # Get system metrics
    # @return [Hash] System-wide metrics
    def system_metrics
      {
        total_users: User.count,
        total_accounts: Account.count,
        active_accounts: Account.where(status: "active").count,
        suspended_accounts: Account.where(status: "suspended").count,
        cancelled_accounts: Account.where(status: "cancelled").count,
        total_subscriptions: Subscription.count,
        active_subscriptions: Subscription.where(status: %w[active trialing]).count,
        trial_subscriptions: Subscription.where(status: "trialing").count,
        total_revenue: Payment.where(status: "completed").sum(:amount_cents) || 0,
        monthly_revenue: calculate_monthly_revenue,
        failed_payments: Payment.where(status: "failed").where("created_at > ?", 30.days.ago).count,
        webhook_events_today: webhook_events_today_count,
        system_health: calculate_system_health,
        uptime: calculate_uptime
      }
    end

    # Get recent users data
    # @param limit [Integer] Number of users to return
    # @return [Array<Hash>] Recent users
    def recent_users_data(limit: 10)
      User.includes(:account)
          .order(created_at: :desc)
          .limit(limit)
          .map { |user| serialize_user(user) }
    end

    # Get recent accounts data
    # @param limit [Integer] Number of accounts to return
    # @return [Array<Hash>] Recent accounts
    def recent_accounts_data(limit: 10)
      Account.includes(:users, subscription: :plan)
             .order(created_at: :desc)
             .limit(limit)
             .map { |account| serialize_account(account) }
    end

    # Get recent system logs
    # @param limit [Integer] Number of logs to return
    # @return [Array<Hash>] Recent logs
    def recent_system_logs(limit: 20)
      AuditLog.includes(:user, :account)
              .order(created_at: :desc)
              .limit(limit)
              .map { |log| serialize_log(log) }
    end

    # Get payment gateway status
    # @return [Hash] Status of payment gateways
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

    # Get platform statistics
    # @return [Hash] Platform-wide statistics
    def platform_statistics
      {
        total_accounts: Account.count,
        active_accounts: Account.where(status: "active").count,
        total_users: User.count,
        active_users: User.where(status: "active").count,
        total_subscriptions: Subscription.count,
        active_subscriptions: Subscription.where(status: %w[active trialing]).count,
        total_revenue: calculate_total_revenue,
        monthly_growth: calculate_monthly_growth
      }
    end

    # Get user management data
    # @return [Hash] User management statistics
    def user_management_data
      {
        total_users: User.count,
        users_by_roles: user_role_distribution,
        users_by_status: User.group(:status).count,
        recent_registrations: User.where(created_at: 7.days.ago..Time.current).count,
        email_verification_pending: User.where(email_verified_at: nil).count
      }
    end

    # Get security settings data
    # @return [Hash] Security-related statistics
    def security_settings_data
      {
        failed_login_attempts_today: AuditLog.where(
          action: "login_failed",
          created_at: Date.current.beginning_of_day..Date.current.end_of_day
        ).count,
        locked_accounts: User.where("locked_until > ?", Time.current).count,
        recent_security_events: AuditLog.where(
          action: %w[login_failed password_change account_locked],
          created_at: 24.hours.ago..Time.current
        ).count,
        suspicious_activities: detect_suspicious_activities
      }
    end

    # Suspend an account
    # @param account_id [String] Account to suspend
    # @param reason [String] Reason for suspension
    # @return [Hash] Result
    def suspend_account(account_id:, reason: nil)
      target_account = Account.find(account_id)

      if target_account.update(status: "suspended")
        log_admin_action("suspend_account", target_account, {
          suspended_account_name: target_account.name,
          reason: reason || "Administrative action"
        })

        { success: true, message: "Account suspended successfully" }
      else
        { success: false, errors: target_account.errors.full_messages }
      end
    rescue ActiveRecord::RecordNotFound
      { success: false, error: "Account not found" }
    end

    # Activate an account
    # @param account_id [String] Account to activate
    # @param reason [String] Reason for activation
    # @return [Hash] Result
    def activate_account(account_id:, reason: nil)
      target_account = Account.find(account_id)

      if target_account.update(status: "active")
        log_admin_action("activate_account", target_account, {
          activated_account_name: target_account.name,
          reason: reason || "Administrative action"
        })

        { success: true, message: "Account activated successfully" }
      else
        { success: false, errors: target_account.errors.full_messages }
      end
    rescue ActiveRecord::RecordNotFound
      { success: false, error: "Account not found" }
    end

    # Get global analytics data (if permitted)
    # @return [Hash] Global analytics
    def global_analytics
      return {} unless user.can?("view_global_analytics")

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

    # Get settings summary
    # @return [Hash] Settings summary with timestamps
    def settings_summary_data
      settings = System::SettingsService.load_settings

      metadata = Rails.cache.fetch("system_settings_metadata", expires_in: 1.year) do
        {
          created_at: Time.current,
          updated_at: Time.current
        }
      end

      settings.merge(metadata)
    end

    private

    def calculate_monthly_revenue
      Payment.where(
        status: "completed",
        created_at: Date.current.beginning_of_month..Date.current.end_of_month
      ).sum(:amount_cents) || 0
    end

    def webhook_events_today_count
      AuditLog.where(
        source: %w[stripe_webhook paypal_webhook],
        created_at: Date.current.beginning_of_day..Date.current.end_of_day
      ).count
    end

    def calculate_system_health
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
      process_start_time = File.stat("/proc/self").ctime rescue (Time.current - 1.day)
      [Time.current - process_start_time, 0].max
    end

    def serialize_user(user)
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

    def serialize_account(account)
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

    def serialize_log(log)
      {
        id: log.id,
        level: determine_log_level(log.action),
        message: format_log_message(log),
        timestamp: log.created_at,
        source: log.source || "system",
        metadata: log.metadata
      }
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

    def user_role_distribution
      role_counts = {}

      User.includes(user_roles: :role).find_each do |u|
        user_roles = u.user_roles.map { |ur| ur.role.name }
        user_roles = ["no_role"] if user_roles.empty?

        user_roles.each do |role_name|
          role_counts[role_name] = (role_counts[role_name] || 0) + 1
        end
      end

      role_counts
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

    def check_unusual_api_activity
      # Check for rate limit violations
      rate_limit_violations = 0

      begin
        cache_keys = Rails.cache.redis.keys("rate_limit:*")

        cache_keys.each do |key|
          current_count = Rails.cache.read(key) || 0
          parts = key.split(":")
          next if parts.length < 4

          controller_name = parts[1]
          limit_type = determine_limit_type(controller_name)
          expected_limit = System::SettingsService.rate_limit_setting(limit_type)

          if expected_limit && current_count >= (expected_limit * 0.8).to_i
            rate_limit_violations += 1
          end
        end
      rescue StandardError => e
        Rails.logger.error "Error checking API activity: #{e.message}"
      end

      rate_limit_violations
    end

    def determine_limit_type(controller_name)
      case controller_name
      when "sessions" then "login_attempts_per_hour"
      when "registrations" then "registration_attempts_per_hour"
      when "passwords" then "password_reset_attempts_per_hour"
      when "webhooks" then "webhook_requests_per_minute"
      else "api_requests_per_minute"
      end
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

    def calculate_global_churn_rate
      active_subscriptions = Subscription.where(status: %w[active trialing]).count
      cancelled_this_month = Subscription.where(
        status: "cancelled",
        updated_at: Date.current.beginning_of_month..Date.current.end_of_month
      ).count

      return 0 if active_subscriptions.zero?
      (cancelled_this_month / active_subscriptions.to_f * 100).round(2)
    end

    def calculate_customer_growth
      Account.group_by_month(:created_at, last: 12).count
    end

    def log_admin_action(action, resource, metadata = {})
      AuditLog.create!(
        user: user,
        account: account,
        action: action,
        resource_type: resource.class.name,
        resource_id: resource.id,
        source: "admin_panel",
        ip_address: Thread.current[:request_ip],
        user_agent: Thread.current[:request_user_agent],
        metadata: metadata
      )
    end
  end
end

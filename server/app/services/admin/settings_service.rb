# frozen_string_literal: true

module Admin
  # Service for managing admin settings and system configuration
  #
  # Provides settings management including:
  # - System metrics and overview
  # - System logs retrieval
  # - Account status management
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

    # Admin overview: metrics and the settings summary only. Activity lists
    # live on their own Administration pages, and billing figures and payment
    # gateway status are an extension's (it contributes its own overview card).
    # @return [Hash]
    def admin_overview
      {
        metrics: system_metrics,
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
        system_health: calculate_system_health,
        uptime: calculate_uptime
      }
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
        total_revenue: (Powernode::BillingBridge.revenue_snapshot_model
                          &.where(account_id: nil)
                          &.order(:snapshot_date)
                          &.last(30)
                          &.pluck(:snapshot_date, :total_revenue) || []),
        subscription_trends: subscription_class ? subscription_class.group(:status).count : {},
        churn_rate: calculate_global_churn_rate,
        customer_growth: calculate_customer_growth
      }
    end

    # Get settings summary
    # @return [Hash] Settings summary with timestamps
    def settings_summary_data
      settings = AdminSetting.all.each_with_object({}) do |setting, hash|
        hash[setting.key.to_sym] = setting.value
      end

      # Override the raw string dump above with the typed reader: AdminSetting
      # stores every value as a string, so the raw "false" the loop above just
      # captured is a non-empty (truthy) JS string on the other end — the
      # overview page badge would read ACTIVE forever. Admin::MaintenanceMode
      # is the single source of truth for this flag.
      settings[:maintenance_mode] = Admin::MaintenanceMode.enabled?

      # Same reasoning for rate_limiting: it is stored as dotted
      # "rate_limiting.<field>" rows (fc-38), not a single row, so the raw
      # dump above never captures it as a nested object at all. Rebuild the
      # nested hash the settings form expects from those rows.
      settings[:rate_limiting] = Admin::SystemSettings.rate_limiting_config

      metadata = Rails.cache.fetch("system_settings_metadata", expires_in: 1.year) do
        {
          created_at: Time.current,
          updated_at: Time.current
        }
      end

      settings.merge(metadata)
    end

    private

    def calculate_system_health
      failed_payments = payment_class&.where(status: "failed", created_at: 24.hours.ago..Time.current)&.count || 0
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
      [ Time.current - process_start_time, 0 ].max
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

    # user_role_distribution's sole caller, user_management_data, was removed
    # here (fc-38), so this went with it rather than being left as dead code.

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
        Powernode::CacheRedis.scan_each(match: "rate_limit:*") do |key|
          current_count = Rails.cache.read(key) || 0
          parts = key.split(":")
          next if parts.length < 4

          controller_name = parts[1]
          limit_type = determine_limit_type(controller_name)
          expected_limit = Admin::SystemSettings.rate_limit(limit_type)

          if expected_limit && current_count >= (expected_limit * 0.8).to_i
            rate_limit_violations += 1
          end
        end  # scan_each
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

    def calculate_global_churn_rate
      return 0 unless subscription_class

      active_subscriptions = subscription_class.where(status: %w[active trialing]).count
      cancelled_this_month = subscription_class.where(
        status: "cancelled",
        updated_at: Date.current.beginning_of_month..Date.current.end_of_month
      ).count

      return 0 if active_subscriptions.zero?
      (cancelled_this_month / active_subscriptions.to_f * 100).round(2)
    end

    def calculate_customer_growth
      Account.group_by_month(:created_at, last: 12).count
    end

    def subscription_class
      Powernode::BillingBridge.subscription_model
    end

    def payment_class
      Powernode::BillingBridge.payment_model
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

# frozen_string_literal: true

module Admin
  # Service for managing admin settings and system configuration
  #
  # Provides settings management including:
  # - System metrics and overview
  # - Account status management
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

    # user_role_distribution's sole caller, user_management_data, was removed
    # here (fc-38), so this went with it rather than being left as dead code.

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

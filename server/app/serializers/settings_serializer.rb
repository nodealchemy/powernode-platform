# frozen_string_literal: true

# The single definition of the /api/v1/settings payload, for BOTH halves of the
# resource: Api::V1::SettingsController#show (the read) and
# SettingsUpdateService (the write, whose result[:data] the controller renders
# straight through).
#
# Extracted from two independently maintained copies of the same four
# serializers, previously kept aligned by "kept in parity with ..." comments.
# Three of the four pairs were still identical. The security section was not,
# and the drift was live: the service hardcoded `two_factor_enabled: false` and
# omitted four fields, so a user with 2FA genuinely enabled who saved an
# unrelated preference got a response claiming 2FA was off, and lost
# two_factor_enabled_at, backup_codes_generated_at, login_history and
# authorized_keys on the write path only. The controller's version was the
# correct one throughout — it reads live state — so it is the version kept here.
#
# Same shape as ActivitySerializer, which was extracted from an identical
# `activity_json` duplicated across two controllers.
#
# The section readers are PUBLIC because three other controller actions
# (notification and preference show/update) render a single section rather than
# the whole payload.
class SettingsSerializer
  def initialize(user:, account:)
    @user = user
    @account = account
  end

  def as_json
    {
      user_preferences: user_preferences,
      account_settings: account_settings,
      notification_preferences: notification_preferences,
      security_settings: security_settings
    }
  end

  def self.serialize(user:, account:)
    new(user: user, account: account).as_json
  end

  def user_preferences
    preferences = @user.preferences || {}

    # Merge with defaults
    {
      theme: preferences["theme"] || "light",
      language: preferences["language"] || "en",
      timezone: preferences["timezone"] || "UTC",
      date_format: preferences["date_format"] || "MM/dd/yyyy",
      currency_display: preferences["currency_display"] || "symbol",
      dashboard_layout: preferences["dashboard_layout"] || "grid",
      analytics_default_period: preferences["analytics_default_period"] || "30_days",
      items_per_page: preferences["items_per_page"] || 25,
      auto_refresh_interval: preferences["auto_refresh_interval"] || 30,
      keyboard_shortcuts_enabled: preferences["keyboard_shortcuts_enabled"] != false
    }
  end

  def account_settings
    settings = @account.settings || {}

    {
      name: @account.name,
      subdomain: @account.subdomain,
      billing_email: @account.billing_email,
      tax_id: @account.tax_id,
      company_size: settings["company_size"],
      industry: settings["industry"],
      website: settings["website"],
      phone: settings["phone"],
      address: settings["address"],
      logo_url: settings["logo_url"],
      # IMP-94728a788498: writable through the PATCH blind settings merge, so it
      # must be readable here too — a misconfigured default fails composes
      # loudly, and the operator needs this surface to inspect/clear it.
      Account::DEFAULT_SDWAN_NETWORK_SETTING.to_sym => settings[Account::DEFAULT_SDWAN_NETWORK_SETTING]
    }
  end

  def notification_preferences
    notifications = @user.notification_preferences || {}

    # Merge with defaults
    {
      email_notifications: notifications["email_notifications"] != false,
      invoice_notifications: notifications["invoice_notifications"] != false,
      security_alerts: notifications["security_alerts"] != false,
      marketing_emails: notifications["marketing_emails"] || false,
      account_updates: notifications["account_updates"] != false,
      system_maintenance: notifications["system_maintenance"] != false,
      new_features: notifications["new_features"] || false,
      usage_reports: notifications["usage_reports"] || false,
      payment_reminders: notifications["payment_reminders"] != false
    }
  end

  def security_settings
    {
      email_verified: @user.email_verified?,
      password_last_changed: @user.password_changed_at,
      # Live predicate (two_factor_secret.present?), never a literal — the
      # write half used to hardcode false here.
      two_factor_enabled: @user.two_factor_enabled?,
      two_factor_enabled_at: @user.two_factor_enabled_at,
      backup_codes_generated_at: @user.two_factor_backup_codes_generated_at,
      login_history: recent_login_history,
      failed_attempts: @user.failed_login_attempts,
      account_locked: @user.locked?,
      authorized_keys: Array(@user.authorized_keys)
    }
  end

  private

  def recent_login_history
    # Get last 5 login audit logs
    @user.audit_logs
         .where(action: "login")
         .order(created_at: :desc)
         .limit(5)
         .pluck(:created_at, :ip_address, :user_agent)
         .map do |created_at, ip, user_agent|
      {
        timestamp: created_at,
        ip_address: ip,
        user_agent: user_agent
      }
    end
  end
end

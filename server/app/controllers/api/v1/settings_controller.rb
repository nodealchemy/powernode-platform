# frozen_string_literal: true

class Api::V1::SettingsController < ApplicationController
  skip_before_action :authenticate_request, only: [ :public ]
  # GET /api/v1/settings/public
  def public
    render_success({
      copyright_text: formatted_copyright_text
    })
  end

  # GET /api/v1/settings
  def show
    # Check if user is authenticated
    unless current_user
      return render_error("Authentication required", status: :unauthorized)
    end

    render_success({
      user_preferences: current_user_preferences,
      account_settings: current_account_settings,
      notification_preferences: current_notification_preferences,
      security_settings: current_security_settings
    })
  end

  # PUT /api/v1/settings
  def update
    result = SettingsUpdateService.new(
      user: current_user,
      account: current_account,
      params: settings_params
    ).call

    if result[:success]
      render_success(result[:data].merge({
        message: "Settings updated successfully"
      }))
    else
      render_error("Settings update failed", :unprocessable_content, details: result[:errors])
    end
  end

  # GET /api/v1/settings/notifications
  def notifications
    render_success(current_notification_preferences)
  end

  # PUT /api/v1/settings/notifications
  def update_notifications
    if update_user_preferences("notifications", notification_params)
      # Broadcast the notification preferences update to all user's sessions
      broadcast_settings_update("notifications_updated", current_notification_preferences)

      render_success(current_notification_preferences.merge({
        message: "Notification preferences updated"
      }))
    else
      render_error("Failed to update notification preferences", :unprocessable_content, details: { errors: current_user.errors.full_messages })
    end
  end

  # GET /api/v1/settings/preferences
  def preferences
    render_success(current_user_preferences)
  end

  # PUT /api/v1/settings/preferences
  def update_preferences
    if update_user_preferences("preferences", preference_params)
      # Broadcast the preferences update to all user's sessions
      broadcast_settings_update("preferences_updated", current_user_preferences)

      render_success(current_user_preferences.merge({
        message: "User preferences updated"
      }))
    else
      render_error("Failed to update preferences", :unprocessable_content, details: { errors: current_user.errors.full_messages })
    end
  end

  private

  def settings_params
    params.require(:settings).permit(
      user_preferences: {},
      account_settings: {},
      notification_preferences: {},
      security_settings: {}
    )
  end

  def notification_params
    params.require(:notifications).permit(
      :email_notifications,
      :invoice_notifications,
      :security_alerts,
      :marketing_emails,
      :account_updates,
      :system_maintenance,
      :new_features,
      :usage_reports,
      :payment_reminders
    )
  end

  def preference_params
    params.require(:preferences).permit(
      :theme,
      :language,
      :timezone,
      :date_format,
      :currency_display,
      :dashboard_layout,
      :analytics_default_period,
      :items_per_page,
      :auto_refresh_interval,
      :keyboard_shortcuts_enabled
    )
  end

  def current_user_preferences
    preferences = current_user.preferences || {}

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

  def current_account_settings
    settings = current_account.settings || {}

    {
      name: current_account.name,
      subdomain: current_account.subdomain,
      billing_email: current_account.billing_email,
      tax_id: current_account.tax_id,
      company_size: settings["company_size"],
      industry: settings["industry"],
      website: settings["website"],
      phone: settings["phone"],
      address: settings["address"],
      logo_url: settings["logo_url"]
    }
  end

  def current_notification_preferences
    notifications = current_user.notification_preferences || {}

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

  def current_security_settings
    {
      email_verified: current_user.email_verified?,
      password_last_changed: current_user.password_changed_at,
      two_factor_enabled: current_user.two_factor_enabled?,
      two_factor_enabled_at: current_user.two_factor_enabled_at,
      backup_codes_generated_at: current_user.two_factor_backup_codes_generated_at,
      login_history: recent_login_history,
      failed_attempts: current_user.failed_login_attempts,
      account_locked: current_user.locked?
    }
  end

  def recent_login_history
    # Get last 5 login audit logs
    current_user.audit_logs
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

  def update_user_preferences(key, new_preferences)
    current_preferences = current_user.send(key) || {}
    updated_preferences = current_preferences.merge(new_preferences.to_h)

    current_user.update(key.to_sym => updated_preferences)
  end

  def broadcast_settings_update(message_type, data)
    # Broadcast to all sessions for the current user's account
    NotificationChannel.broadcast_to(
      current_account,
      {
        type: message_type,
        data: data,
        user_id: current_user.id,
        timestamp: Time.current.iso8601
      }
    )
  rescue StandardError => e
    Rails.logger.error "Failed to broadcast settings update: #{e.message}"
  end

  def formatted_copyright_text
    copyright_template = System::SettingsService.get_setting(:copyright_text) || "© {year} Powernode Platform. All rights reserved."
    copyright_template.gsub("{year}", Date.current.year.to_s)
  end
end

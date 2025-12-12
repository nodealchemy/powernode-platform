# frozen_string_literal: true

class SettingsUpdateService
  def initialize(user:, account:, params:)
    @user = user
    @account = account
    @params = params
    @errors = []
  end

  def call
    result = { success: true, data: {}, errors: [] }

    ActiveRecord::Base.transaction do
      update_user_preferences if @params[:user_preferences].present?
      update_account_settings if @params[:account_settings].present?
      update_notification_preferences if @params[:notification_preferences].present?
      update_security_settings if @params[:security_settings].present?

      raise ActiveRecord::Rollback if @errors.any?
    end

    if @errors.any?
      result[:success] = false
      result[:errors] = @errors
    else
      result[:data] = {
        user_preferences: current_user_preferences,
        account_settings: current_account_settings,
        notification_preferences: current_notification_preferences,
        security_settings: current_security_settings
      }
    end

    result
  end

  private

  def update_user_preferences
    preferences = @user.preferences || {}
    new_preferences = preferences.merge(@params[:user_preferences].to_h)

    unless @user.update(preferences: new_preferences)
      @errors.concat(@user.errors.full_messages)
    end
  end

  def update_account_settings
    account_params = @params[:account_settings].to_h
    settings_params = {}
    account_update_params = {}

    # Separate direct account fields from settings hash
    account_fields = %w[name subdomain billing_email tax_id]
    account_fields.each do |field|
      if account_params.key?(field)
        account_update_params[field] = account_params.delete(field)
      end
    end

    # Remaining params go to settings hash
    if account_params.any?
      current_settings = @account.settings || {}
      settings_params = current_settings.merge(account_params)
      account_update_params[:settings] = settings_params
    end

    unless @account.update(account_update_params)
      @errors.concat(@account.errors.full_messages)
    end
  end

  def update_notification_preferences
    current_notifications = @user.notification_preferences || {}
    new_notifications = current_notifications.merge(@params[:notification_preferences].to_h)

    unless @user.update(notification_preferences: new_notifications)
      @errors.concat(@user.errors.full_messages)
    end
  end

  def update_security_settings
    security_params = @params[:security_settings].to_h

    # Handle password change
    if security_params[:password].present? && security_params[:current_password].present?
      if @user.authenticate(security_params[:current_password])
        unless @user.update(
          password: security_params[:password],
          password_confirmation: security_params[:password_confirmation]
        )
          @errors.concat(@user.errors.full_messages)
        end
      else
        @errors << "Current password is incorrect"
      end
    end

    # Handle email change
    if security_params[:email].present? && security_params[:email] != @user.email
      @user.email = security_params[:email]
      @user.email_verified_at = nil # Reset email verification

      unless @user.save
        @errors.concat(@user.errors.full_messages)
      end
    end
  end

  def current_user_preferences
    preferences = @user.preferences || {}

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
      logo_url: settings["logo_url"]
    }
  end

  def current_notification_preferences
    notifications = @user.notification_preferences || {}

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
      email_verified: @user.email_verified?,
      password_last_changed: @user.password_changed_at,
      two_factor_enabled: false,
      failed_attempts: @user.failed_login_attempts,
      account_locked: @user.locked?
    }
  end
end

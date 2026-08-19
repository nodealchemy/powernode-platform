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
      # IMP-550e44e24220 follow-up — ONE definition, shared with
      # Api::V1::SettingsController. This service used to carry its own copy of
      # all four serializers; the security one had drifted (a hardcoded
      # two_factor_enabled: false plus four missing fields), so the write half
      # of this resource described it differently from the read half.
      result[:data] = SettingsSerializer.serialize(user: @user, account: @account)
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
end

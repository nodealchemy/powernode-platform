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

    if (message = unusable_sdwan_default_error(account_params))
      @errors << message
      return
    end

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

  # IMP-529b8514bbc6 — WRITE-SIDE SCREEN for the one settings key that has a
  # read-side fail-loud guard.
  #
  # This method merges arbitrary keys into `Account#settings`, which is exactly
  # what makes the surface useful and exactly how a form or API client that
  # types `default_sdwan_network_id` as a number or an object stores a value
  # nothing here objects to. The only component that ever complains is
  # PlanComposerService#check_network_declaration, at compose time, to whoever
  # happens to provision next — which is the right refusal in the wrong place
  # and at the wrong moment.
  #
  # DEFENCE IN DEPTH, NOT A REPLACEMENT: the read-side guard is unchanged and
  # must stay, because it is the only thing that speaks for values written
  # before this screen existed or by any other writer of the jsonb column.
  #
  # Screened through the SAME classifier both network resolvers read, so
  # "unusable" means one thing platform-wide and this cannot drift into
  # rejecting a value the composer would have accepted: blank/null/0 (no
  # default) and the explicit "none" opt-out all stay legal, and any non-blank
  # String is accepted here exactly as the composer accepts it — existence is
  # deliberately not decided at either end.
  def unusable_sdwan_default_error(account_params)
    key = ::Account::DEFAULT_SDWAN_NETWORK_SETTING
    return nil unless account_params.key?(key) || account_params.key?(key.to_sym)

    raw = account_params.key?(key) ? account_params[key] : account_params[key.to_sym]
    state, = ::Shared::SdwanNetworkResolution.classify_value(raw)
    return nil unless state == :unusable

    "#{key} must be a network id, " \
      "#{::Shared::SdwanNetworkResolution::NETWORK_OPT_OUT_VALUE.inspect} to opt out of the " \
      "fabric, or blank/0 to set no default"
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

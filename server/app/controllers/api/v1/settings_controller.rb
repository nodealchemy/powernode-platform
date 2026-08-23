# frozen_string_literal: true

class Api::V1::SettingsController < ApplicationController
  skip_before_action :authenticate_request, only: [ :public ]

  # IMP-e639a38f4d8c — #update is FOUR writers behind one route, and only one of
  # them leaves the caller's own row.
  #
  #   user_preferences / notification_preferences / security_settings
  #       -> columns on the CALLING User (theme, notification opt-ins, own
  #          password + own email). Self-service by definition; every
  #          authenticated user may write them, and the frontend does exactly
  #          that for every user (ThemeContext, ProfilePage).
  #   account_settings
  #       -> the SHARED Account row. SettingsUpdateService#update_account_settings
  #          blind-merges whatever is left into the `settings` jsonb (company
  #          profile, default_sdwan_network_id — which decides the fabric every
  #          future instance lands on — and any other key a consumer reads out
  #          of that column) AND lifts name/subdomain/billing_email/tax_id
  #          straight onto the account.
  #
  # That second group is account-wide configuration, and the OTHER writer of the
  # same column, Api::V1::AccountsController#update, has always required
  # `admin.settings.update`. This action required nothing, which made it the
  # more capable of the two doors: AccountsController permits :settings as a
  # SCALAR (strong params drops a Hash, so it cannot write nested settings at
  # all) while this one permits `account_settings: {}` and can write anything.
  # One column now has one permission behind both doors.
  #
  # Gated on the PRESENCE of the key, not on its contents: a request that
  # mentions account_settings at all is asking to write account state, so this
  # predicate can never be looser than the service's own
  # `@params[:account_settings].present?` guard even if that guard is later
  # relaxed. No frontend caller sends the section (all four call sites PUT a
  # single self-service section), so nothing legitimate is caught by it.
  #
  # require_permission raises PermissionDenied, which halts the filter chain
  # before the service runs — the row is not written and then refused.
  before_action :authorize_account_settings_write!, only: [ :update ]

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

  # PUT /api/v1/settings/ssh_keys
  # Replaces the current user's authorized_keys with the supplied
  # OpenSSH lines. The User model's `authorized_keys=` setter
  # deduplicates + compacts, and `validate :authorized_keys_format`
  # rejects malformed lines (returned as 422 details). Aggregated
  # across the account by System::Node#authorized_keys and pulled by
  # each agent on heartbeat — no per-node push needed.
  def update_ssh_keys
    keys = Array(params[:keys] || params.dig(:settings, :keys))
    if current_user.update(authorized_keys: keys)
      render_success(
        authorized_keys: Array(current_user.authorized_keys),
        message: "SSH keys updated"
      )
    else
      render_error(
        "Failed to update SSH keys",
        :unprocessable_content,
        details: { errors: current_user.errors.full_messages }
      )
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

  # Reads the raw params rather than settings_params so the gate does not
  # depend on the permit-list: any shape of account_settings, permitted or not,
  # is still an attempt to write account-wide state.
  def authorize_account_settings_write!
    return unless params[:settings].respond_to?(:key?) && params[:settings].key?(:account_settings)

    require_permission("admin.settings.update")
  end

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

  # IMP-550e44e24220 follow-up — the payload now has ONE definition
  # (SettingsSerializer), shared with SettingsUpdateService so the read and
  # write halves of this resource cannot drift. These stay as named readers
  # because #show and three single-section actions below render them
  # individually. Built fresh per call rather than memoized: the preference and
  # notification update actions serialize AFTER mutating current_user.
  def settings_serializer
    SettingsSerializer.new(user: current_user, account: current_account)
  end

  def current_user_preferences
    settings_serializer.user_preferences
  end

  def current_account_settings
    settings_serializer.account_settings
  end

  def current_notification_preferences
    settings_serializer.notification_preferences
  end

  def current_security_settings
    settings_serializer.security_settings
  end

  def update_user_preferences(key, new_preferences)
    # Map key to actual attribute name
    attribute_key = case key
    when "notifications" then "notification_preferences"
    else key
    end

    current_preferences = current_user.send(attribute_key) || {}
    updated_preferences = current_preferences.merge(new_preferences.to_h)

    current_user.update(attribute_key.to_sym => updated_preferences)
  end

  def broadcast_settings_update(message_type, data)
    # Broadcast to all sessions for the current user's account, using the same
    # per-account stream NotificationChannel subscribers listen on.
    NotificationChannel.broadcast_to_account(
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
    copyright_template = AdminSetting.find_by(key: "copyright_text")&.value || "© {year} Everett C. Haimes III"
    copyright_template.gsub("{year}", Date.current.year.to_s)
  end
end

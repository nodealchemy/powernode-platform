# frozen_string_literal: true

module Review
  class NotificationPreference < ApplicationRecord
    include AuditLogging

    # Associations
    belongs_to :account

    # Validations
    validates :account_id, uniqueness: true
    validates :preferences, presence: true
    validates :delivery_channels, presence: true
    validates :frequency, inclusion: { in: %w[immediate hourly daily weekly disabled] }
    validates :quiet_hours_start, :quiet_hours_end,
              numericality: { in: 0..23 },
              allow_nil: true

    # Scopes
    scope :with_email_enabled, -> { where("delivery_channels ? 'email'") }
    scope :with_push_enabled, -> { where("delivery_channels ? 'push'") }
    scope :with_sms_enabled, -> { where("delivery_channels ? 'sms'") }
    scope :immediate_delivery, -> { where(frequency: "immediate") }
    scope :digest_users, -> { where(frequency: [ "hourly", "daily", "weekly" ]) }

    # Default preferences for new accounts
    def self.default_preferences
      {
        "new_review" => { "enabled" => true, "channels" => [ "email", "in_app" ] },
        "review_response" => { "enabled" => true, "channels" => [ "email", "in_app", "push" ] },
        "review_flagged" => { "enabled" => true, "channels" => [ "email" ] },
        "review_approved" => { "enabled" => true, "channels" => [ "in_app", "push" ] },
        "review_rejected" => { "enabled" => true, "channels" => [ "email", "in_app" ] },
        "review_milestone" => { "enabled" => true, "channels" => [ "email", "in_app" ] },
        "helpful_vote" => { "enabled" => false, "channels" => [ "in_app" ] },
        "review_digest" => { "enabled" => true, "channels" => [ "email" ] },
        "admin_alert" => { "enabled" => true, "channels" => [ "email", "push" ] }
      }
    end

    def self.default_channels
      %w[email in_app push]
    end

    # Create default preferences for a new account
    def self.create_for_account(account)
      create!(
        account: account,
        preferences: default_preferences,
        delivery_channels: default_channels,
        frequency: "immediate"
      )
    end

    # Check if notifications are enabled for a specific type
    def enabled_for?(notification_type)
      return false if disabled?

      pref = preferences[notification_type.to_s]
      return false unless pref

      pref["enabled"] == true
    end

    # Get enabled channels for a notification type
    def channels_for(notification_type)
      return [] unless enabled_for?(notification_type)

      pref = preferences[notification_type.to_s]
      configured_channels = pref["channels"] || []

      # Return intersection of configured channels and account's enabled channels
      configured_channels & delivery_channels
    end

    # Check if delivery should be delayed based on quiet hours
    def in_quiet_hours?(time = Time.current)
      return false unless quiet_hours_start && quiet_hours_end

      hour = time.hour

      if quiet_hours_start < quiet_hours_end
        # Normal range (e.g., 22 to 6)
        hour >= quiet_hours_start && hour < quiet_hours_end
      else
        # Overnight range (e.g., 22 to 6 next day)
        hour >= quiet_hours_start || hour < quiet_hours_end
      end
    end

    # Check if account should receive digest notifications
    def digest_enabled?
      %w[hourly daily weekly].include?(frequency)
    end

    # Status methods
    def disabled?
      frequency == "disabled"
    end

    def immediate_delivery?
      frequency == "immediate"
    end

    # Update preferences for specific notification types
    def update_preference(notification_type, enabled: nil, channels: nil)
      current_prefs = preferences.dup
      current_prefs[notification_type.to_s] ||= {}

      current_prefs[notification_type.to_s]["enabled"] = enabled unless enabled.nil?
      current_prefs[notification_type.to_s]["channels"] = channels if channels

      update!(preferences: current_prefs)
    end

    # Bulk update multiple preferences
    def update_preferences(updates)
      current_prefs = preferences.dup

      updates.each do |notification_type, settings|
        current_prefs[notification_type.to_s] ||= {}
        current_prefs[notification_type.to_s].merge!(settings)
      end

      update!(preferences: current_prefs)
    end

    # Enable/disable specific delivery channels
    def toggle_channel(channel, enabled)
      new_channels = delivery_channels.dup

      if enabled && !new_channels.include?(channel)
        new_channels << channel
      elsif !enabled
        new_channels.delete(channel)
      end

      update!(delivery_channels: new_channels)
    end

    # Get summary of current settings
    def settings_summary
      {
        frequency: frequency,
        channels_enabled: delivery_channels,
        quiet_hours: quiet_hours_configured?,
        total_enabled_types: enabled_notification_types.count,
        digest_enabled: digest_enabled?
      }
    end

    def enabled_notification_types
      preferences.select { |_, settings| settings["enabled"] == true }.keys
    end

    def quiet_hours_configured?
      quiet_hours_start && quiet_hours_end
    end

    # Calculate next delivery time based on frequency
    def next_digest_time
      case frequency
      when "hourly"
        1.hour.from_now.beginning_of_hour
      when "daily"
        1.day.from_now.beginning_of_day + digest_time.hours
      when "weekly"
        1.week.from_now.beginning_of_week + digest_day.days + digest_time.hours
      else
        nil
      end
    end

    private

    def digest_time
      # Default to 9 AM for daily/weekly digests
      9
    end

    def digest_day
      # Default to Monday (1) for weekly digests
      1
    end
  end
end

# Backward compatibility alias
ReviewNotificationPreference = Review::NotificationPreference unless defined?(ReviewNotificationPreference)

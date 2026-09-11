# frozen_string_literal: true

class AdminSetting < ApplicationRecord
  include ServiceConfiguration

  validates :key, presence: true, uniqueness: true

  # Get a setting value by key
  def self.get(key, default_value = nil)
    setting = find_by(key: key.to_s)
    return default_value unless setting

    # Try to deserialize JSON, fall back to string value
    begin
      JSON.parse(setting.value)
    rescue JSON::ParserError
      setting.value
    end
  end

  # Set a setting value by key
  def self.set(key, value)
    serialized_value = value.is_a?(String) ? value : value.to_json

    setting = find_or_initialize_by(key: key.to_s)
    setting.value = serialized_value
    setting.save!

    setting
  end

  EMAIL_VERIFICATION_EXPIRY_HOURS_KEY = "email_verification_expiry_hours"
  EMAIL_VERIFICATION_EXPIRY_HOURS_DEFAULT = 24
  EMAIL_VERIFICATION_EXPIRY_HOURS_MAX = 720 # 30 days

  # Single source of truth for the email-verification-link expiry window.
  # User#email_verification_expired? (the check) and the email settings API
  # (what notification_mailer.rb tells the user) both read through here, so
  # the promised and enforced windows cannot drift.
  #
  # The stored value is trusted as-is by .get (secreview 22): unset, "0",
  # negative, non-numeric, blank, or a JSON boolean/array/object must all
  # fall back to the default rather than expiring every token instantly or
  # 500ing; an absurdly large value (a literal "never expires") is capped
  # rather than honored.
  def self.email_verification_expiry_hours
    raw = get(EMAIL_VERIFICATION_EXPIRY_HOURS_KEY, EMAIL_VERIFICATION_EXPIRY_HOURS_DEFAULT)
    value = begin
      Integer(raw)
    rescue ArgumentError, TypeError
      EMAIL_VERIFICATION_EXPIRY_HOURS_DEFAULT
    end
    value = EMAIL_VERIFICATION_EXPIRY_HOURS_DEFAULT if value <= 0
    [ value, EMAIL_VERIFICATION_EXPIRY_HOURS_MAX ].min
  end

  # Whether a candidate value (as it would arrive from a write door's
  # params) is acceptable to store for email_verification_expiry_hours: an
  # integer in 1..MAX. Used by the write door to REFUSE a bad value up
  # front, rather than storing it and relying on the reader's fallback.
  def self.valid_email_verification_expiry_hours?(value)
    Integer(value).between?(1, EMAIL_VERIFICATION_EXPIRY_HOURS_MAX)
  rescue ArgumentError, TypeError
    false
  end

  # Set multiple settings at once
  def self.set_many(settings_hash)
    settings_hash.each do |key, value|
      set(key, value)
    end
  end

  # Get all settings as a hash
  def self.to_hash
    all.each_with_object({}) do |setting, hash|
      hash[setting.key.to_sym] = begin
        JSON.parse(setting.value)
      rescue JSON::ParserError
        setting.value
      end
    end
  end
end

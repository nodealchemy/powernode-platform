# frozen_string_literal: true

class AdminSetting < ApplicationRecord
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

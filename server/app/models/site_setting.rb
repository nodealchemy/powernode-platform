# frozen_string_literal: true

class SiteSetting < ApplicationRecord
  
  # Validations
  validates :key, presence: true, uniqueness: { case_sensitive: false }
  validates :setting_type, presence: true, inclusion: { in: %w[string text boolean integer json] }
  validates :value, presence: true, unless: ->(setting) { setting.setting_type == 'boolean' || setting.key.in?(%w[social_facebook social_twitter social_linkedin social_instagram social_youtube analytics_tracking_id]) }
  
  # Callbacks
  after_save :clear_footer_cache_if_needed
  after_destroy :clear_footer_cache_if_needed
  
  # Scopes
  scope :public_settings, -> { where(is_public: true) }
  scope :by_type, ->(type) { where(setting_type: type) }
  scope :footer_settings, -> { where(key: footer_keys) }
  
  # Class methods
  def self.footer_keys
    %w[
      site_name
      copyright_text
      copyright_year
      social_facebook
      social_twitter
      social_linkedin
      social_instagram
      social_youtube
      footer_description
      company_address
      contact_email
      contact_phone
    ]
  end
  
  def self.get(key)
    setting = find_by(key: key.to_s)
    return nil unless setting
    
    case setting.setting_type
    when 'boolean'
      setting.value.to_s.downcase.in?(['true', '1', 'yes'])
    when 'integer'
      setting.value.to_i
    when 'json'
      JSON.parse(setting.value) rescue {}
    else
      setting.value
    end
  end
  
  def self.set(key, value, description: nil, setting_type: 'string', is_public: false)
    setting = find_or_initialize_by(key: key.to_s)
    
    setting.value = case setting_type
                    when 'json'
                      value.is_a?(String) ? value : value.to_json
                    when 'boolean'
                      value.to_s
                    else
                      value.to_s
                    end
                    
    setting.description = description if description
    setting.setting_type = setting_type
    setting.is_public = is_public
    setting.save!
    setting
  end
  
  def self.footer_settings
    settings = where(key: footer_keys)
    settings.each_with_object({}) do |setting, hash|
      hash[setting.key] = get(setting.key)
    end
  end
  
  def self.public_footer_settings
    cache_enabled = get('footer_cache_enabled')
    cache_key = 'site_settings:footer:public'
    
    if cache_enabled
      Rails.cache.fetch(cache_key, expires_in: 1.hour) do
        fetch_footer_settings_data
      end
    else
      fetch_footer_settings_data
    end
  end
  
  # Clear footer cache when footer settings are updated
  def self.clear_footer_cache!
    Rails.cache.delete('site_settings:footer:public')
  end
  
  private_class_method def self.fetch_footer_settings_data
    public_settings.where(key: footer_keys).each_with_object({}) do |setting, hash|
      hash[setting.key] = get(setting.key)
    end
  end
  
  # Instance methods
  def parsed_value
    self.class.get(key)
  end
  
  private
  
  def boolean_type?
    setting_type == 'boolean'
  end
  
  def can_be_blank?
    # Allow these fields to be blank
    key.in?(%w[
      social_facebook
      social_twitter
      social_linkedin
      social_instagram
      social_youtube
      analytics_tracking_id
    ])
  end
  
  def clear_footer_cache_if_needed
    # Clear cache if this is a footer setting or the cache toggle itself
    if self.class.footer_keys.include?(key) || key == 'footer_cache_enabled'
      self.class.clear_footer_cache!
    end
  end
end

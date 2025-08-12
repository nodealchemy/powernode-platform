class ApiKey < ApplicationRecord
  # Associations
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :account, optional: true
  has_many :api_key_usages, dependent: :destroy

  # Validations
  validates :name, presence: true, length: { maximum: 100 }
  validates :key_hash, presence: true, uniqueness: true
  validates :status, presence: true, inclusion: { in: %w[active revoked expired] }
  validates :expires_at, comparison: { greater_than: :created_at }, allow_nil: true

  # Serialization
  serialize :scopes, coder: JSON
  serialize :allowed_ips, coder: JSON
  serialize :metadata, coder: JSON

  # Scopes
  scope :active, -> { where(status: 'active').where('expires_at IS NULL OR expires_at > ?', Time.current) }
  scope :revoked, -> { where(status: 'revoked') }
  scope :expired, -> { where('expires_at <= ?', Time.current) }

  # Callbacks
  before_validation :set_defaults
  before_create :generate_key
  after_update :log_status_change

  # Virtual attributes
  attr_accessor :key_value

  # Class methods
  def self.available_scopes
    [
      'read:users',
      'write:users', 
      'read:accounts',
      'write:accounts',
      'read:subscriptions',
      'write:subscriptions',
      'read:payments',
      'write:payments',
      'read:invoices',
      'write:invoices',
      'read:analytics',
      'admin:settings',
      'admin:impersonation',
      'webhooks:manage'
    ]
  end

  def self.scope_descriptions
    {
      'read:users' => 'Read user information and profiles',
      'write:users' => 'Create, update, and delete users',
      'read:accounts' => 'Read account information and settings',
      'write:accounts' => 'Update account settings and configuration',
      'read:subscriptions' => 'Read subscription details and history',
      'write:subscriptions' => 'Manage subscriptions and billing',
      'read:payments' => 'Read payment history and methods',
      'write:payments' => 'Process payments and manage payment methods',
      'read:invoices' => 'Read invoice details and history',
      'write:invoices' => 'Generate and manage invoices',
      'read:analytics' => 'Access analytics and reporting data',
      'admin:settings' => 'Manage system settings and configuration',
      'admin:impersonation' => 'Impersonate users for support purposes',
      'webhooks:manage' => 'Configure and manage webhook endpoints'
    }
  end

  def self.find_by_key(key_value)
    return nil unless key_value.present?
    
    key_hash = hash_key(key_value)
    find_by(key_hash: key_hash)
  end

  def self.hash_key(key_value)
    Digest::SHA256.hexdigest("#{Rails.application.secret_key_base}:#{key_value}")
  end

  # Instance methods
  def active?
    status == 'active' && !expired?
  end

  def revoked?
    status == 'revoked'
  end

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def valid_for_use?
    active? && !rate_limited?
  end

  def invalid_reason
    return 'API key is revoked' if revoked?
    return 'API key has expired' if expired?
    return 'Rate limit exceeded' if rate_limited?
    return 'API key is inactive' unless active?
    nil
  end

  def regenerate_key!
    transaction do
      old_key_hash = key_hash
      generate_key
      save!
      
      # Log the regeneration
      Rails.logger.info "API key #{id} regenerated (old hash: #{old_key_hash[0..7]}...)"
    end
  end

  def masked_key
    return nil unless key_prefix.present?
    "#{key_prefix}...#{key_suffix}"
  end

  def has_scope?(required_scope)
    return true if scopes.blank? # No scope restrictions
    return true if scopes.include?('*') # Wildcard access
    
    scopes.include?(required_scope) || 
    scopes.any? { |scope| scope_matches?(scope, required_scope) }
  end

  def record_usage!(request_data = {})
    increment!(:usage_count)
    update!(last_used_at: Time.current)
    
    # Create detailed usage record
    api_key_usages.create!(
      endpoint: request_data[:endpoint],
      http_method: request_data[:method],
      status_code: request_data[:status],
      ip_address: request_data[:ip_address],
      user_agent: request_data[:user_agent],
      request_count: 1,
      metadata: request_data[:metadata] || {}
    )
  end

  def requests_today
    usage_count_for_period(Date.current.beginning_of_day..Date.current.end_of_day)
  end

  def requests_this_week
    usage_count_for_period(1.week.ago..Time.current)
  end

  def requests_this_month
    usage_count_for_period(1.month.ago..Time.current)
  end

  def average_requests_per_day
    return 0 if usage_count.zero? || created_at > 1.day.ago
    
    days_active = [(Time.current - created_at) / 1.day, 1].max
    (usage_count.to_f / days_active).round(2)
  end

  def rate_limited?
    return false unless rate_limit_per_hour || rate_limit_per_day

    if rate_limit_per_hour && requests_in_last_hour >= rate_limit_per_hour
      return true
    end

    if rate_limit_per_day && requests_today >= rate_limit_per_day
      return true
    end

    false
  end

  def requests_in_last_hour
    usage_count_for_period(1.hour.ago..Time.current)
  end

  def ip_allowed?(ip_address)
    return true if allowed_ips.blank?
    allowed_ips.include?(ip_address)
  end

  private

  def set_defaults
    self.status ||= 'active'
    self.scopes ||= []
    self.allowed_ips ||= []
    self.usage_count ||= 0
    self.rate_limit_per_hour ||= SystemSettingsService.get_setting('api_keys.default_hourly_limit', 1000)
    self.rate_limit_per_day ||= SystemSettingsService.get_setting('api_keys.default_daily_limit', 10000)
    self.metadata ||= {}
  end

  def generate_key
    # Generate a secure random key
    random_bytes = SecureRandom.random_bytes(32)
    self.key_value = "pk_#{Rails.env.production? ? 'live' : 'test'}_#{SecureRandom.urlsafe_base64(32)}"
    self.key_hash = self.class.hash_key(key_value)
    self.key_prefix = key_value[0..15]
    self.key_suffix = key_value[-8..-1]
  end

  def scope_matches?(scope_pattern, required_scope)
    # Handle wildcard patterns like "read:*" matching "read:users"
    if scope_pattern.end_with?('*')
      prefix = scope_pattern[0..-2]
      required_scope.start_with?(prefix)
    else
      scope_pattern == required_scope
    end
  end

  def usage_count_for_period(time_range)
    api_key_usages.where(created_at: time_range).sum(:request_count)
  end

  def log_status_change
    if saved_change_to_status?
      Rails.logger.info "API key #{id} (#{name}) status changed from #{status_before_last_save} to #{status}"
    end
  end
end
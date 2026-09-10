# frozen_string_literal: true

class ApiKey < ApplicationRecord
  # Associations
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :account, optional: true
  has_many :api_key_usages, dependent: :destroy

  # Validations
  validates :name, presence: true, length: { maximum: 100 }
  validates :key_digest, presence: true, uniqueness: true
  validates :is_active, inclusion: { in: [ true, false ] }
  validates :expires_at, comparison: { greater_than: :created_at }, allow_nil: true

  # Note: scopes, allowed_ips, and metadata are JSON columns
  # and don't need explicit serialization in Rails 8

  # Scopes
  scope :active, -> { where(is_active: true).where("expires_at IS NULL OR expires_at > ?", Time.current) }
  scope :inactive, -> { where(is_active: false) }
  scope :expired, -> { where("expires_at <= ?", Time.current) }
  scope :revoked, -> { where(is_active: false) }

  # Callbacks
  before_validation :set_defaults
  before_validation :generate_key, on: :create
  after_update :log_status_change

  # Virtual attributes
  attr_accessor :key_value

  # Class methods
  def self.available_scopes
    [
      "read:users",
      "write:users",
      "read:accounts",
      "write:accounts",
      "read:subscriptions",
      "write:subscriptions",
      "read:payments",
      "write:payments",
      "read:invoices",
      "write:invoices",
      "read:analytics",
      "admin:settings",
      "admin:impersonation",
      "webhooks:manage"
    ]
  end

  def self.scope_descriptions
    {
      "read:users" => "Read user information and profiles",
      "write:users" => "Create, update, and delete users",
      "read:accounts" => "Read account information and settings",
      "write:accounts" => "Update account settings and configuration",
      "read:subscriptions" => "Read subscription details and history",
      "write:subscriptions" => "Manage subscriptions and billing",
      "read:payments" => "Read payment history and methods",
      "write:payments" => "Process payments and manage payment methods",
      "read:invoices" => "Read invoice details and history",
      "write:invoices" => "Generate and manage invoices",
      "read:analytics" => "Access analytics and reporting data",
      "admin:settings" => "Manage system settings and configuration",
      "admin:impersonation" => "Impersonate users for support purposes",
      "webhooks:manage" => "Configure and manage webhook endpoints"
    }
  end

  def self.find_by_key(key_value)
    return nil unless key_value.present?

    key_digest = hash_key(key_value)
    find_by(key_digest: key_digest)
  end

  def self.hash_key(key_value)
    Digest::SHA256.hexdigest("#{Rails.application.secret_key_base}:#{key_value}")
  end

  # Instance methods
  def active?
    is_active && !expired?
  end

  def revoked?
    !is_active
  end

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def valid_for_use?
    active? && !rate_limited?
  end

  def invalid_reason
    return "API key is inactive" if revoked?
    return "API key has expired" if expired?
    return "Rate limit exceeded" if rate_limited?
    return "API key is inactive" unless active?
    nil
  end

  def regenerate_key!
    transaction do
      old_key_digest = key_digest
      generate_key
      save!

      # Log the regeneration
      Rails.logger.info "API key #{id} regenerated (old digest: #{old_key_digest[0..7]}...)"
    end
  end

  def masked_key
    return nil unless prefix.present?
    "#{prefix}...****"
  end

  def has_scope?(required_scope)
    return true if permissions.blank? # No scope restrictions
    return true if permissions.include?("*") # Wildcard access

    permissions.include?(required_scope) ||
    permissions.any? { |scope| scope_matches?(scope, required_scope) }
  end

  # Records that the key was used. The counter half always applies; the
  # detailed row is written only when the caller can supply what the table
  # requires (IMP-01a07d5a).
  #
  # api_key_usages.endpoint / method / response_status are all NOT NULL, and
  # an AUTHENTICATOR does not yet know the response status — it runs before the
  # action. This used to be called with NO arguments at all from
  # a2a_controller.rb, so every create! passed three nils into NOT NULL columns.
  # That never surfaced because the model raised earlier still (see
  # ApiKeyUsage), and the one caller rescued StandardError into nil, taking the
  # whole authentication down with it silently.
  #
  # So the detail row is now the caller's choice: pass the request context once
  # the status is known (the A2A controller does it in an after_action) and a
  # row is written; call it bare from an authenticator and only the counters
  # move. Nothing is invented to satisfy a NOT NULL constraint — a placeholder
  # endpoint would be worse than no row.
  #
  # usage_count is incremented here as well. The column exists and is surfaced
  # by api_keys_controller (`usage_count: api_key.usage_count || 0`), and
  # nothing has ever written it, so every key has always reported 0.
  def record_usage!(request_data = {})
    self.class.where(id: id).update_all(
      last_used_at: Time.current,
      usage_count: ApiKey.arel_table[:usage_count] + 1,
      updated_at: Time.current
    )
    reload

    return nil unless detailed_usage_recordable?(request_data)

    api_key_usages.create!(
      endpoint: request_data[:endpoint],
      method: request_data[:method],
      response_status: request_data[:status],
      ip_address: request_data[:ip_address],
      user_agent: request_data[:user_agent],
      request_params: request_data[:params] || {},
      used_at: Time.current
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

  def rate_limited?
    return false if rate_limits.blank?

    hourly_limit = rate_limits["hourly"]
    daily_limit = rate_limits["daily"]

    if hourly_limit && requests_in_last_hour >= hourly_limit
      return true
    end

    if daily_limit && requests_today >= daily_limit
      return true
    end

    false
  end

  def requests_in_last_hour
    usage_count_for_period(1.hour.ago..Time.current)
  end

  private

  # The three NOT NULL columns a detail row needs. Checked rather than
  # defaulted: a row invented around missing data would make the usage table
  # look populated while describing nothing.
  def detailed_usage_recordable?(request_data)
    request_data[:endpoint].present? &&
      request_data[:method].present? &&
      request_data[:status].present?
  end

  def set_defaults
    self.is_active = true if is_active.nil?
    self.permissions ||= []
    self.rate_limits ||= {}
  end

  def generate_key
    # Generate a secure random key
    random_bytes = SecureRandom.random_bytes(32)
    self.key_value = "pk_#{Rails.env.production? ? 'live' : 'test'}_#{SecureRandom.urlsafe_base64(32)}"
    self.key_digest = self.class.hash_key(key_value)
    self.prefix = key_value[0..15]
  end

  def scope_matches?(scope_pattern, required_scope)
    # Handle wildcard patterns like "read:*" matching "read:users"
    if scope_pattern.end_with?("*")
      prefix = scope_pattern[0..-2]
      required_scope.start_with?(prefix)
    else
      scope_pattern == required_scope
    end
  end

  def usage_count_for_period(time_range)
    api_key_usages.where(used_at: time_range).count
  end

  def log_status_change
    if saved_change_to_is_active?
      Rails.logger.info "API key #{id} (#{name}) is_active changed from #{is_active_before_last_save} to #{is_active}"
    end
  end
end

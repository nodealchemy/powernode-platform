# frozen_string_literal: true

class WebhookEndpoint < ApplicationRecord
  # Associations
  belongs_to :account
  belongs_to :created_by, class_name: "User", optional: true
  has_many :webhook_deliveries, dependent: :destroy
  has_many :webhook_events, through: :webhook_deliveries
  has_many :delivery_stats, class_name: "WebhookDeliveryStat", dependent: :destroy

  # Validations
  validates :url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }
  validates :status, presence: true, inclusion: { in: %w[active inactive] }
  validates :content_type, presence: true, inclusion: {
    in: %w[application/json application/x-www-form-urlencoded]
  }
  validates :timeout_seconds, presence: true, numericality: {
    greater_than: 0, less_than_or_equal_to: 300
  }
  validates :retry_limit, presence: true, numericality: {
    greater_than_or_equal_to: 0, less_than_or_equal_to: 10
  }
  validates :retry_backoff, presence: true, inclusion: { in: %w[linear exponential] }
  validates :description, length: { maximum: 500 }, allow_blank: true

  # Note: event_types and metadata are JSON columns in PostgreSQL
  # They have native JSON serialization, no need for explicit serialize calls

  # Scopes
  scope :active, -> { where(status: "active", is_active: true) }
  scope :inactive, -> { where.not(status: "active").or(where(is_active: false)) }
  scope :for_event_type, ->(event_type) { where("event_types @> ?", [ event_type ].to_json) }
  scope :recent_deliveries, -> { where(last_delivery_at: 24.hours.ago..Time.current) }
  scope :high_success_rate, -> { where("CASE WHEN (success_count + failure_count) > 0 THEN (success_count::float / (success_count + failure_count)) > 0.95 ELSE true END") }
  scope :failing, -> { where("CASE WHEN (success_count + failure_count) > 0 THEN (success_count::float / (success_count + failure_count)) < 0.5 ELSE false END") }

  # Callbacks
  before_validation :set_defaults
  before_create :generate_secret_token
  after_update :log_status_change

  # Class methods
  def self.available_event_types
    [
      # User events
      "user.created", "user.updated", "user.deleted", "user.login", "user.logout",

      # Account events
      "account.created", "account.updated", "account.suspended", "account.activated",

      # Subscription events
      "subscription.created", "subscription.updated", "subscription.cancelled",
      "subscription.trial_started", "subscription.trial_ended",

      # Payment events
      "payment.created", "payment.completed", "payment.failed", "payment.refunded",

      # Invoice events
      "invoice.created", "invoice.sent", "invoice.paid", "invoice.overdue",

      # Plan events
      "plan.created", "plan.updated", "plan.deleted",

      # System events
      "system.maintenance_start", "system.maintenance_end",

      # Test events
      "test.webhook"
    ]
  end

  def self.event_categories
    {
      "User Management" => %w[user.created user.updated user.deleted user.login user.logout],
      "Account Management" => %w[account.created account.updated account.suspended account.activated],
      "Billing & Subscriptions" => %w[subscription.created subscription.updated subscription.cancelled payment.completed payment.failed invoice.created invoice.paid],
      "System Events" => %w[system.maintenance_start system.maintenance_end],
      "Testing" => %w[test.webhook]
    }
  end

  def self.content_type_options
    [
      [ "JSON (application/json)", "application/json" ],
      [ "Form Data (application/x-www-form-urlencoded)", "application/x-www-form-urlencoded" ]
    ]
  end

  def self.retry_backoff_options
    [
      [ "Exponential (recommended)", "exponential" ],
      [ "Linear", "linear" ]
    ]
  end

  # Payload detail level options
  PAYLOAD_DETAIL_LEVELS = %w[full minimal ids_only].freeze

  # Instance methods
  def active?
    status == "active" && is_active? && !circuit_broken?
  end

  def inactive?
    !active?
  end

  # Circuit Breaker Methods

  def circuit_broken?
    circuit_broken_at.present? && circuit_cooldown_until.present? && circuit_cooldown_until > Time.current
  end

  def circuit_break!
    update!(
      circuit_broken_at: Time.current,
      circuit_cooldown_until: calculate_circuit_cooldown
    )
    Rails.logger.warn "Circuit breaker triggered for webhook endpoint #{id} (#{url})"
  end

  def circuit_reset!
    update!(
      consecutive_failures: 0,
      circuit_broken_at: nil,
      circuit_cooldown_until: nil
    )
    Rails.logger.info "Circuit breaker reset for webhook endpoint #{id}"
  end

  def record_success!
    if consecutive_failures > 0 || circuit_broken_at.present?
      circuit_reset!
    end
    increment_success_count!
  end

  def record_failure!
    new_consecutive = consecutive_failures + 1
    update_column(:consecutive_failures, new_consecutive)

    if new_consecutive >= (circuit_break_threshold || 5)
      circuit_break!
    end
    increment_failure_count!
  end

  def circuit_status
    return "closed" unless circuit_broken_at.present?
    return "open" if circuit_cooldown_until.present? && circuit_cooldown_until > Time.current

    "half_open"
  end

  def time_until_circuit_reset
    return nil unless circuit_cooldown_until.present?
    return 0 if circuit_cooldown_until <= Time.current

    (circuit_cooldown_until - Time.current).to_i
  end

  def success_rate
    total = success_count + failure_count
    return 100.0 if total.zero?
    (success_count.to_f / total * 100).round(2)
  end

  def failure_rate
    100.0 - success_rate
  end

  def total_deliveries
    success_count + failure_count
  end

  def health_status
    return "unknown" if total_deliveries.zero?
    return "excellent" if success_rate >= 95.0
    return "good" if success_rate >= 85.0
    return "warning" if success_rate >= 70.0
    "critical"
  end

  def average_response_time
    successful_deliveries = webhook_deliveries.successful.where.not(attempted_at: nil)
    return 0 if successful_deliveries.empty?
    avg_seconds = successful_deliveries.average(Arel.sql("EXTRACT(EPOCH FROM (attempted_at - created_at))"))
    return 0 unless avg_seconds
    (avg_seconds * 1000).round(2) # Convert to milliseconds
  end

  def last_success_at
    webhook_deliveries.successful.maximum(:attempted_at)
  end

  def last_failure_at
    webhook_deliveries.failed.maximum(:attempted_at)
  end

  def can_receive_event?(event_type)
    active? && (event_types.blank? || event_types.include?(event_type) || event_types.include?("*"))
  end

  def regenerate_secret!
    self.secret_key = generate_secret_token_value
    save!
  end

  def masked_secret
    return nil unless secret_key.present?
    "#{secret_key[0..7]}#{'*' * 24}#{secret_key[-8..-1]}"
  end

  def increment_success_count!
    increment!(:success_count)
    update_column(:last_delivery_at, Time.current)
  end

  def increment_failure_count!
    increment!(:failure_count)
    update_column(:last_delivery_at, Time.current)
  end

  def reset_counters!
    update!(success_count: 0, failure_count: 0, last_delivery_at: nil)
  end

  def next_retry_delay(attempt_number)
    base_delay = 5 # seconds

    case retry_backoff
    when "linear"
      base_delay * attempt_number
    when "exponential"
      base_delay * (2 ** (attempt_number - 1))
    else
      base_delay
    end.clamp(1, 300) # Max 5 minutes
  end

  # Tier-related methods
  TIER_LIMITS = {
    "free" => 100,
    "pro" => 10_000,
    "enterprise" => Float::INFINITY
  }.freeze

  def tier
    self[:tier] || "free"
  end

  def tier_daily_limit
    TIER_LIMITS[tier] || 100
  end

  def rate_limited?
    return false if tier == "enterprise"

    daily_count >= tier_daily_limit
  end

  def can_deliver?
    active? && !rate_limited? && !circuit_broken?
  end

  # Payload trimming based on detail level
  def trim_payload(payload)
    return payload if payload_detail_level == "full"

    case payload_detail_level
    when "minimal"
      trim_payload_minimal(payload)
    when "ids_only"
      trim_payload_ids_only(payload)
    else
      payload
    end
  end

  def increment_daily_count!
    reset_daily_count_if_needed!
    increment!(:daily_count)
  end

  def reset_daily_count_if_needed!
    return if daily_count_reset_at && daily_count_reset_at > Time.current.beginning_of_day

    update_columns(
      daily_count: 0,
      daily_count_reset_at: Time.current.beginning_of_day
    )
  end

  def remaining_daily_deliveries
    return Float::INFINITY if tier == "enterprise"

    [ tier_daily_limit - daily_count, 0 ].max
  end

  def generate_signature(payload)
    return nil unless signature_secret.present?

    timestamp = Time.current.to_i
    payload_string = "#{timestamp}.#{payload}"
    signature = OpenSSL::HMAC.hexdigest("SHA256", signature_secret, payload_string)

    "t=#{timestamp},v1=#{signature}"
  end

  def verify_signature(payload, signature_header)
    return false unless signature_secret.present? && signature_header.present?

    parts = signature_header.split(",").each_with_object({}) do |part, hash|
      key, value = part.split("=", 2)
      hash[key] = value
    end

    timestamp = parts["t"]&.to_i
    signature = parts["v1"]

    return false unless timestamp && signature

    # Verify timestamp is within 5 minutes
    return false if (Time.current.to_i - timestamp).abs > 300

    expected_payload = "#{timestamp}.#{payload}"
    expected_signature = OpenSSL::HMAC.hexdigest("SHA256", signature_secret, expected_payload)

    ActiveSupport::SecurityUtils.secure_compare(signature, expected_signature)
  end

  def regenerate_signature_secret!
    self.signature_secret = "whsig_#{SecureRandom.base64(32).tr('+/', '-_')}"
    save!
  end

  def analytics_summary(days: 30)
    WebhookDeliveryStat.aggregate_for_endpoint(self, days: days)
  end

  # Custom headers validation
  def validate_custom_headers
    return if custom_headers.blank?

    if custom_headers.is_a?(Hash) && custom_headers.keys.length > 20
      errors.add(:custom_headers, "cannot exceed 20 headers")
    end
  end

  private

  def calculate_circuit_cooldown
    # Exponential backoff for circuit breaker: 1min, 5min, 15min, 1hr, 4hr (max)
    base_minutes = [ 1, 5, 15, 60, 240 ]
    # Use consecutive failures to determine cooldown duration
    failures_over_threshold = [ consecutive_failures - (circuit_break_threshold || 5), 0 ].max
    cooldown_index = [ failures_over_threshold, base_minutes.length - 1 ].min
    base_minutes[cooldown_index].minutes.from_now
  end

  def trim_payload_minimal(payload)
    return {} unless payload.is_a?(Hash)

    {
      event_type: payload[:event_type] || payload["event_type"],
      timestamp: payload[:timestamp] || payload["timestamp"] || Time.current.iso8601,
      id: payload[:id] || payload["id"],
      action: payload[:action] || payload["action"],
      account_id: payload[:account_id] || payload["account_id"]
    }.compact
  end

  def trim_payload_ids_only(payload)
    return {} unless payload.is_a?(Hash)

    extract_ids(payload)
  end

  def extract_ids(obj, prefix = "")
    result = {}
    return result unless obj.is_a?(Hash)

    obj.each do |key, value|
      full_key = prefix.empty? ? key.to_s : "#{prefix}_#{key}"
      if key.to_s.end_with?("_id") || key.to_s == "id"
        result[full_key] = value
      elsif value.is_a?(Hash)
        result.merge!(extract_ids(value, full_key))
      end
    end
    result
  end

  def set_defaults
    self.status ||= "active"
    self.is_active = true if is_active.nil?
    self.timeout_seconds ||= 30
    self.max_retries ||= 3
    self.retry_limit ||= 3
    self.retry_backoff ||= "exponential"
    self.content_type ||= "application/json"
    self.event_types ||= []
    self.headers ||= {}
  end

  def generate_secret_token
    self.secret_key ||= generate_secret_token_value
  end

  def generate_secret_token_value
    "whsec_#{SecureRandom.base64(32).tr('+/', '-_')}"
  end

  def log_status_change
    if saved_change_to_status?
      Rails.logger.info "Webhook endpoint #{id} status changed from #{status_before_last_save} to #{status}"
    end
  end
end

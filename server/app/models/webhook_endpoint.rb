# frozen_string_literal: true

class WebhookEndpoint < ApplicationRecord
  # Associations
  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true
  has_many :webhook_deliveries, dependent: :destroy
  has_many :webhook_events, dependent: :destroy

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
  scope :active, -> { where(status: 'active', is_active: true) }
  scope :inactive, -> { where.not(status: 'active').or(where(is_active: false)) }
  scope :for_event_type, ->(event_type) { where("event_types @> ?", [event_type].to_json) }
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
      'user.created', 'user.updated', 'user.deleted', 'user.login', 'user.logout',
      
      # Account events
      'account.created', 'account.updated', 'account.suspended', 'account.activated',
      
      # Subscription events
      'subscription.created', 'subscription.updated', 'subscription.cancelled',
      'subscription.trial_started', 'subscription.trial_ended',
      
      # Payment events
      'payment.created', 'payment.completed', 'payment.failed', 'payment.refunded',
      
      # Invoice events
      'invoice.created', 'invoice.sent', 'invoice.paid', 'invoice.overdue',
      
      # Plan events
      'plan.created', 'plan.updated', 'plan.deleted',
      
      # System events
      'system.maintenance_start', 'system.maintenance_end',
      
      # Test events
      'test.webhook'
    ]
  end

  def self.event_categories
    {
      'User Management' => %w[user.created user.updated user.deleted user.login user.logout],
      'Account Management' => %w[account.created account.updated account.suspended account.activated],
      'Billing & Subscriptions' => %w[subscription.created subscription.updated subscription.cancelled payment.completed payment.failed invoice.created invoice.paid],
      'System Events' => %w[system.maintenance_start system.maintenance_end],
      'Testing' => %w[test.webhook]
    }
  end

  def self.content_type_options
    [
      ['JSON (application/json)', 'application/json'],
      ['Form Data (application/x-www-form-urlencoded)', 'application/x-www-form-urlencoded']
    ]
  end

  def self.retry_backoff_options
    [
      ['Exponential (recommended)', 'exponential'],
      ['Linear', 'linear']
    ]
  end

  # Instance methods
  def active?
    status == 'active' && is_active?
  end

  def inactive?
    !active?
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
    return 'unknown' if total_deliveries.zero?
    return 'excellent' if success_rate >= 95.0
    return 'good' if success_rate >= 85.0
    return 'warning' if success_rate >= 70.0
    'critical'
  end

  def average_response_time
    successful_deliveries = webhook_deliveries.successful.where.not(response_time_ms: nil)
    return 0 if successful_deliveries.empty?
    successful_deliveries.average(:response_time_ms)&.round(2) || 0
  end

  def last_success_at
    webhook_deliveries.successful.maximum(:completed_at)
  end

  def last_failure_at
    webhook_deliveries.failed.maximum(:completed_at)
  end

  def can_receive_event?(event_type)
    active? && (event_types.blank? || event_types.include?(event_type) || event_types.include?('*'))
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
    when 'linear'
      base_delay * attempt_number
    when 'exponential'
      base_delay * (2 ** (attempt_number - 1))
    else
      base_delay
    end.clamp(1, 300) # Max 5 minutes
  end

  private

  def set_defaults
    self.status ||= 'active'
    self.is_active = true if is_active.nil?
    self.timeout_seconds ||= 30
    self.max_retries ||= 3
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
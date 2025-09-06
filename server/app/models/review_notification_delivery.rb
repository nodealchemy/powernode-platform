# frozen_string_literal: true

class ReviewNotificationDelivery < ApplicationRecord
  include AuditLogging
  
  # Associations
  belongs_to :review_notification
  
  # Validations
  validates :delivery_channel, presence: true, inclusion: {
    in: %w[email sms push in_app webhook slack],
    message: "must be a valid delivery channel"
  }
  validates :status, presence: true, inclusion: {
    in: %w[pending processing sent failed bounced opened clicked],
    message: "must be a valid delivery status"
  }
  
  # Scopes
  scope :by_channel, ->(channel) { where(delivery_channel: channel) }
  scope :successful, -> { where(status: %w[sent opened clicked]) }
  scope :failed, -> { where(status: %w[failed bounced]) }
  scope :pending, -> { where(status: 'pending') }
  scope :recent, -> { order(created_at: :desc) }
  
  # Status methods
  def pending?
    status == 'pending'
  end
  
  def processing?
    status == 'processing'
  end
  
  def sent?
    %w[sent opened clicked].include?(status)
  end
  
  def failed?
    %w[failed bounced].include?(status)
  end
  
  def opened?
    %w[opened clicked].include?(status)
  end
  
  def clicked?
    status == 'clicked'
  end
  
  # Delivery tracking methods
  def mark_processing!
    update!(
      status: 'processing',
      processed_at: Time.current
    )
  end
  
  def mark_sent!(external_id = nil, provider_response = nil)
    update!(
      status: 'sent',
      sent_at: Time.current,
      external_id: external_id,
      provider_response: provider_response
    )
  end
  
  def mark_failed!(error_message, provider_response = nil)
    update!(
      status: 'failed',
      failed_at: Time.current,
      error_message: error_message,
      provider_response: provider_response
    )
  end
  
  def mark_bounced!(bounce_reason = nil)
    update!(
      status: 'bounced',
      bounced_at: Time.current,
      bounce_reason: bounce_reason
    )
  end
  
  def mark_opened!(opened_at = Time.current)
    update!(
      status: 'opened',
      opened_at: opened_at
    ) unless clicked? # Don't downgrade from clicked to opened
  end
  
  def mark_clicked!(clicked_at = Time.current)
    update!(
      status: 'clicked',
      clicked_at: clicked_at,
      opened_at: opened_at || clicked_at # Assume opened if clicked
    )
  end
  
  # Retry logic
  def can_retry?
    failed? && retry_count < max_retries_for_channel
  end
  
  def retry_delivery!
    return false unless can_retry?
    
    update!(
      status: 'pending',
      retry_count: retry_count + 1,
      next_retry_at: calculate_next_retry_time,
      error_message: nil
    )
    
    true
  end
  
  # Analytics methods
  def delivery_time_seconds
    return nil unless sent_at && created_at
    
    (sent_at - created_at).to_f
  end
  
  def engagement_time_seconds
    return nil unless opened_at && sent_at
    
    (opened_at - sent_at).to_f
  end
  
  # Channel-specific methods
  def email_delivery?
    delivery_channel == 'email'
  end
  
  def push_delivery?
    delivery_channel == 'push'
  end
  
  def sms_delivery?
    delivery_channel == 'sms'
  end
  
  def webhook_delivery?
    delivery_channel == 'webhook'
  end
  
  # Class methods for analytics
  def self.delivery_stats_by_channel(days_back = 7)
    start_date = days_back.days.ago
    
    where('created_at >= ?', start_date)
      .group(:delivery_channel, :status)
      .count
  end
  
  def self.success_rate_by_channel(days_back = 7)
    start_date = days_back.days.ago
    deliveries = where('created_at >= ?', start_date)
    
    channels = deliveries.distinct.pluck(:delivery_channel)
    
    channels.map do |channel|
      channel_deliveries = deliveries.where(delivery_channel: channel)
      total = channel_deliveries.count
      successful = channel_deliveries.successful.count
      
      {
        channel: channel,
        total_deliveries: total,
        successful_deliveries: successful,
        success_rate: total.zero? ? 0.0 : (successful.to_f / total * 100).round(2)
      }
    end
  end
  
  def self.average_delivery_time_by_channel
    where.not(sent_at: nil)
      .group(:delivery_channel)
      .average('EXTRACT(EPOCH FROM (sent_at - created_at))')
      .transform_values { |seconds| seconds&.round(2) }
  end
  
  def self.engagement_metrics(days_back = 7)
    start_date = days_back.days.ago
    
    email_deliveries = where(delivery_channel: 'email', created_at: start_date..)
    push_deliveries = where(delivery_channel: 'push', created_at: start_date..)
    
    {
      email: {
        sent: email_deliveries.where(status: %w[sent opened clicked]).count,
        opened: email_deliveries.where(status: %w[opened clicked]).count,
        clicked: email_deliveries.where(status: 'clicked').count,
        open_rate: calculate_rate(email_deliveries, %w[opened clicked]),
        click_rate: calculate_rate(email_deliveries, %w[clicked])
      },
      push: {
        sent: push_deliveries.where(status: %w[sent opened clicked]).count,
        opened: push_deliveries.where(status: %w[opened clicked]).count,
        clicked: push_deliveries.where(status: 'clicked').count,
        open_rate: calculate_rate(push_deliveries, %w[opened clicked]),
        click_rate: calculate_rate(push_deliveries, %w[clicked])
      }
    }
  end
  
  def self.calculate_rate(scope, statuses)
    total = scope.where(status: %w[sent opened clicked]).count
    return 0.0 if total.zero?
    
    target = scope.where(status: statuses).count
    (target.to_f / total * 100).round(2)
  end
  
  private
  
  def max_retries_for_channel
    case delivery_channel
    when 'email' then 3
    when 'push' then 2
    when 'sms' then 2
    when 'webhook' then 5
    else 2
    end
  end
  
  def calculate_next_retry_time
    # Exponential backoff based on retry count
    delay_minutes = case retry_count
                   when 1 then 5
                   when 2 then 30
                   when 3 then 120
                   else 480 # 8 hours
                   end
    
    delay_minutes.minutes.from_now
  end
end
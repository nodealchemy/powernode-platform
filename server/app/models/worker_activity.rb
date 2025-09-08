# frozen_string_literal: true

# Worker Activity Model
# Tracks activity and usage of workers
class WorkerActivity < ApplicationRecord
  self.table_name = 'worker_activities'
  # Associations
  belongs_to :worker
  
  # Validations
  validates :activity_type, presence: true, length: { maximum: 100 }
  validates :occurred_at, presence: true
  # IP address validation moved to details JSON field
  
  # Attribute types for enums  
  attribute :activity_type, :string
  
  # Enums
  enum :activity_type, {
    authentication: 'authentication',
    job_enqueue: 'job_enqueue',
    api_request: 'api_request',
    health_check: 'health_check',
    web_interface_access: 'web_interface_access',
    admin_action: 'admin_action',
    error_occurred: 'error_occurred',
    service_setup: 'service_setup',
    service_created: 'service_created',
    service_updated: 'service_updated',
    service_deleted: 'service_deleted',
    token_regenerated: 'token_regenerated',
    service_suspended: 'service_suspended',
    service_activated: 'service_activated',
    service_revoked: 'service_revoked',
    ping_test: 'ping_test',
    job_processing_test: 'job_processing_test'
  }, prefix: :activity_type
  
  # Scopes
  scope :recent, -> { where('occurred_at > ?', 24.hours.ago) }
  scope :by_action, ->(action) { where(activity_type: action) }
  scope :successful, -> { where("details->>'status' = 'success'") }
  scope :failed, -> { where("details->>'status' IN ('error', 'failure')") }
  
  # Callbacks
  before_create :set_occurred_at
  
  # Class methods
  def self.log_activity(worker, action, details = {})
    create!(
      worker: worker,
      activity_type: action,
      details: details.merge(
        logged_at: Time.current.iso8601,
        ip_address: details[:ip_address],
        user_agent: details[:user_agent]
      ).compact,
      occurred_at: Time.current
    )
  end
  
  def self.activity_summary(worker, hours = 24)
    activities = where(worker: worker)
                 .where('occurred_at > ?', hours.hours.ago)
    
    # Create hourly breakdown manually since group_by_hour isn't available
    requests_by_hour = {}
    (0...hours).each do |hour_ago|
      hour_start = hour_ago.hours.ago.beginning_of_hour
      hour_end = hour_start + 1.hour
      hour_key = hour_start.strftime('%Y-%m-%d %H:00')
      requests_by_hour[hour_key] = activities.where(occurred_at: hour_start...hour_end).count
    end
    
    {
      total_requests: activities.count,
      successful_requests: activities.successful.count,
      failed_requests: activities.failed.count,
      unique_actions: activities.distinct.pluck(:activity_type),
      last_activity: activities.order(:occurred_at).last&.occurred_at,
      requests_by_hour: requests_by_hour
    }
  end
  
  # Instance methods
  def successful?
    details&.dig('status') == 'success'
  end
  
  def failed?
    ['error', 'failure'].include?(details&.dig('status'))
  end
  
  def duration
    return nil unless details&.dig('duration')
    details['duration'].to_f
  end
  
  def error_message
    details&.dig('error_message')
  end
  
  def request_path
    details&.dig('request_path')
  end
  
  def response_status
    details&.dig('response_status')
  end
  
  private
  
  def set_occurred_at
    self.occurred_at ||= Time.current
  end
end
# Worker Activity Model
# Tracks activity and usage of workers
class WorkerActivity < ApplicationRecord
  self.table_name = 'worker_activities'
  # Associations
  belongs_to :worker
  
  # Validations
  validates :action, presence: true, length: { maximum: 100 }
  validates :performed_at, presence: true
  validates :ip_address, format: { with: /\A(?:[0-9]{1,3}\.){3}[0-9]{1,3}\z|\A(?:[0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}\z/ }, allow_blank: true
  
  # Enums
  enum :action, {
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
    service_revoked: 'service_revoked'
  }, prefix: :action
  
  # Scopes
  scope :recent, -> { where('performed_at > ?', 24.hours.ago) }
  scope :by_action, ->(action) { where(action: action) }
  scope :successful, -> { where("details->>'status' = 'success'") }
  scope :failed, -> { where("details->>'status' IN ('error', 'failure')") }
  
  # Callbacks
  before_create :set_performed_at
  
  # Class methods
  def self.log_activity(service, action, details = {})
    create!(
      service: service,
      action: action,
      details: details.merge(logged_at: Time.current.iso8601),
      performed_at: Time.current,
      ip_address: details[:ip_address],
      user_agent: details[:user_agent]
    )
  end
  
  def self.activity_summary(worker, hours = 24)
    activities = where(worker: worker)
                 .where('performed_at > ?', hours.hours.ago)
    
    # Create hourly breakdown manually since group_by_hour isn't available
    requests_by_hour = {}
    (0...hours).each do |hour_ago|
      hour_start = hour_ago.hours.ago.beginning_of_hour
      hour_end = hour_start + 1.hour
      hour_key = hour_start.strftime('%Y-%m-%d %H:00')
      requests_by_hour[hour_key] = activities.where(performed_at: hour_start...hour_end).count
    end
    
    {
      total_requests: activities.count,
      successful_requests: activities.successful.count,
      failed_requests: activities.failed.count,
      unique_actions: activities.distinct.pluck(:action),
      last_activity: activities.order(:performed_at).last&.performed_at,
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
  
  def set_performed_at
    self.performed_at ||= Time.current
  end
end
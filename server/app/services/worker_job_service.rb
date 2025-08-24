# frozen_string_literal: true

# Service for enqueueing jobs in the standalone worker service
# Communicates with worker via HTTP API
class WorkerJobService
  include HTTParty
  
  base_uri Rails.application.credentials.worker_api_url || 'http://localhost:4567'
  
  class << self
    # Billing jobs
    def enqueue_billing_automation(subscription_id = nil, delay: nil)
      enqueue_job('Billing::BillingAutomationJob', [subscription_id], delay: delay)
    end
    
    def enqueue_payment_retry(subscription_id, failure_type = 'payment_failure', attempt_number = 1, delay: nil)
      enqueue_job('Billing::PaymentRetryJob', [subscription_id, failure_type, attempt_number], delay: delay)
    end
    
    def enqueue_subscription_lifecycle(action, subscription_id, **options)
      enqueue_job('Billing::SubscriptionLifecycleJob', [action, subscription_id], options: options)
    end
    
    def enqueue_billing_scheduler(date = Date.current, delay: nil)
      enqueue_job('Billing::BillingSchedulerJob', [date.iso8601], delay: delay)
    end
    
    def enqueue_billing_cleanup(delay: nil)
      enqueue_job('Billing::BillingCleanupJob', [], delay: delay)
    end
    
    # Report jobs  
    def enqueue_report_generation(report_params, delay: nil)
      enqueue_job('Reports::GenerateReportJob', [report_params], delay: delay)
    end
    
    def enqueue_scheduled_report(scheduled_report_id, delay: nil)
      enqueue_job('Reports::ScheduledReportJob', [scheduled_report_id], delay: delay)
    end
    
    # Webhook jobs
    def enqueue_webhook_processing(webhook_data, delay: nil)
      enqueue_job('Webhooks::ProcessWebhookJob', [webhook_data], delay: delay)
    end
    
    # Analytics jobs
    def enqueue_analytics_recalculation(start_date, end_date, account_id: nil, period_type: "daily", delay: nil)
      args = [start_date.iso8601, end_date.iso8601]
      options = { account_id: account_id, period_type: period_type }.compact
      enqueue_job('Analytics::RecalculateAnalyticsJob', args, options: options, delay: delay)
    end
    
    def enqueue_revenue_snapshot_update(date = Date.current, period_type = "daily", delay: nil)
      enqueue_job('Analytics::UpdateRevenueSnapshotsJob', [date.iso8601, period_type], delay: delay)
    end
    
    # Email jobs
    def enqueue_notification_email(email_type, params = {}, delay: nil)
      enqueue_job('SendNotificationEmailJob', [{ type: email_type, params: params }], delay: delay, queue: 'email')
    end
    
    def enqueue_password_reset_email(user_id, delay: nil)
      enqueue_job('SendNotificationEmailJob', [{ 'type' => 'password_reset', 'params' => { 'user_id' => user_id } }], delay: delay, queue: 'email')
    end
    
    def enqueue_refresh_email_settings(delay: nil)
      enqueue_job('RefreshEmailSettingsJob', [], delay: delay, queue: 'email')
    end
    
    def enqueue_test_email(email, delay: nil)
      enqueue_job('TestEmailJob', [{ email: email }], delay: delay, queue: 'email')
    end
    
    # Advanced email jobs for notification system
    def enqueue_email_delivery(email_data, delay: nil)
      enqueue_job('Notifications::EmailDeliveryJob', [email_data], delay: delay, queue: 'email')
    end
    
    def enqueue_bulk_email(bulk_email_data, delay: nil)
      enqueue_job('Notifications::BulkEmailJob', [bulk_email_data], delay: delay, queue: 'email')
    end
    
    def enqueue_transactional_email(email_data, delay: nil)
      enqueue_job('Notifications::TransactionalEmailJob', [email_data], delay: delay, queue: 'email')
    end
    
    def enqueue_welcome_email(user_id, temp_password, delay: nil)
      enqueue_job('SendNotificationEmailJob', [{ 'type' => 'welcome_user', 'params' => { 'user_id' => user_id, 'temp_password' => temp_password } }], delay: delay, queue: 'email')
    end
    
    private
    
    def enqueue_job(job_class, args = [], options: {}, delay: nil, queue: nil)
      job_data = {
        job_class: job_class,
        args: args,
        options: options,
        delay: delay,
        queue: queue
      }.compact
      
      begin
        response = post('/api/v1/jobs', {
          body: job_data.to_json,
          headers: {
            'Content-Type' => 'application/json',
            'Authorization' => "Bearer #{service_token}",
            'Accept' => 'application/json'
          },
          timeout: 10
        })
        
        if response.success?
          Rails.logger.info "Enqueued job #{job_class} in worker service: #{response.parsed_response['job_id']}"
          response.parsed_response
        else
          Rails.logger.error "Failed to enqueue job #{job_class}: #{response.code} - #{response.message}"
          raise WorkerServiceError, "Failed to enqueue job: #{response.message}"
        end
        
      rescue Timeout::Error, Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout => e
        Rails.logger.error "Worker service connection failed for #{job_class}: #{e.message}"
        raise WorkerServiceError, "Worker service unavailable: #{e.message}"
      rescue StandardError => e
        Rails.logger.error "Unexpected error enqueueing #{job_class}: #{e.message}"
        raise WorkerServiceError, "Job enqueueing failed: #{e.message}"
      end
    end
    
    def service_token
      Rails.application.credentials.worker_service_token ||
        ENV['WORKER_SERVICE_TOKEN'] ||
        generate_service_token
    end
    
    def generate_service_token
      # Generate a service token for worker communication
      payload = {
        service: 'backend',
        type: 'service',
        exp: 24.hours.from_now.to_i
      }
      JWT.encode(payload, Rails.application.config.jwt_secret_key, 'HS256')
    end
  end
  
  # Custom exceptions
  class WorkerServiceError < StandardError; end
  class ConfigurationError < StandardError; end
end
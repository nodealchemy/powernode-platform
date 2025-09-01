# Background Job Engineer Specialist Guide

## Role & Responsibilities

The Background Job Engineer specializes in Sidekiq background processing, job scheduling, queue management, and worker service coordination for Powernode's subscription platform.

### Core Responsibilities
- Setting up Sidekiq for background processing
- Creating scheduled jobs for renewals and billing
- Implementing job retry and failure handling
- Monitoring job performance and queues
- Handling job prioritization and queue management

### Key Focus Areas
- Reliable job processing and retry mechanisms
- Queue optimization and performance monitoring
- Worker service integration and delegation
- Automated scheduling and recurring tasks
- Job failure handling and alerting

## Background Job Architecture Standards

### 1. Sidekiq Configuration (MANDATORY)

#### Sidekiq Setup and Configuration
```ruby
# config/initializers/sidekiq.rb
require 'sidekiq/web'
require 'sidekiq-cron'

Sidekiq.configure_server do |config|
  config.redis = { 
    url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'),
    network_timeout: 5,
    pool_timeout: 5
  }
  
  # Queue configuration with priorities
  config.queues = %w[critical high default low batch]
  
  # Enable cron jobs
  config.on(:startup) do
    Sidekiq::Cron::Job.load_from_hash(cron_jobs_config)
  end
  
  # Job lifecycle callbacks
  config.server_middleware do |chain|
    chain.add JobMetricsMiddleware
    chain.add JobAuditMiddleware
    chain.add ErrorNotificationMiddleware
  end
end

Sidekiq.configure_client do |config|
  config.redis = { 
    url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'),
    network_timeout: 5,
    pool_timeout: 5
  }
end

# Sidekiq Web UI configuration
Sidekiq::Web.use(Rack::Auth::Basic) do |user, password|
  [user, password] == [ENV['SIDEKIQ_USERNAME'], ENV['SIDEKIQ_PASSWORD']]
end

# Dead job retention
Sidekiq.configure_server do |config|
  config.death_handlers << ->(job, ex) do
    JobFailureNotificationService.call(
      job_class: job['class'],
      job_args: job['args'],
      error: ex.message,
      retry_count: job['retry_count']
    )
  end
end

def cron_jobs_config
  {
    'subscription_renewals' => {
      'cron' => '0 9 * * *',  # Daily at 9 AM
      'class' => 'SubscriptionRenewalSchedulerJob',
      'queue' => 'high'
    },
    'billing_cleanup' => {
      'cron' => '0 2 * * *',  # Daily at 2 AM
      'class' => 'BillingCleanupJob',
      'queue' => 'low'
    },
    'dunning_process' => {
      'cron' => '0 10 * * *', # Daily at 10 AM
      'class' => 'DunningProcessSchedulerJob',
      'queue' => 'high'
    },
    'analytics_aggregation' => {
      'cron' => '0 1 * * *',  # Daily at 1 AM
      'class' => 'AnalyticsAggregationJob',
      'queue' => 'default'
    },
    'webhook_retry' => {
      'cron' => '*/15 * * * *', # Every 15 minutes
      'class' => 'WebhookRetryJob',
      'queue' => 'default'
    },
    'system_health_check' => {
      'cron' => '*/5 * * * *',  # Every 5 minutes
      'class' => 'SystemHealthCheckJob',
      'queue' => 'low'
    }
  }
end
```

#### Queue Configuration and Routing
```ruby
# config/sidekiq.yml
---
:queues:
  - [critical, 10]
  - [high, 5]
  - [default, 3]
  - [low, 1]
  - [batch, 1]

:max_retries: 3
:timeout: 30

:scheduler:
  :enabled: true
  :dynamic: true

production:
  :concurrency: 20
  :queues:
    - [critical, 15]
    - [high, 10]
    - [default, 5]
    - [low, 2]
    - [batch, 1]

development:
  :concurrency: 5
  :queues:
    - [critical, 5]
    - [high, 3]
    - [default, 2]
    - [low, 1]
```

### 2. Standard BaseJob Pattern (CRITICAL)

#### Discovered BaseJob Implementation
**MANDATORY**: All worker jobs must inherit from the standardized BaseJob pattern discovered in platform analysis.

```ruby
# app/jobs/base_job.rb - Actual platform implementation
require 'sidekiq'

class BaseJob
  include Sidekiq::Job

  # Common job configuration
  sidekiq_options retry: 3, 
                  dead: true,
                  queue: 'default'

  # Exponential backoff retry strategy with API error handling
  sidekiq_retry_in do |count, exception|
    case exception
    when BackendApiClient::ApiError
      # API errors get shorter retry intervals
      [30, 60, 180][count - 1] || 300
    else
      # Other errors use exponential backoff
      (count ** 4) + 15 + (rand(30) * (count + 1))
    end
  end

  def perform(*args)
    @started_at = Time.current
    logger.info "Starting #{self.class.name} with args: #{args.inspect}"
    
    execute(*args)
    
    @finished_at = Time.current
    duration = @finished_at - @started_at
    logger.info "Completed #{self.class.name} in #{duration.round(2)}s"
  rescue StandardError => e
    @finished_at = Time.current
    duration = @finished_at - @started_at
    logger.error "Failed #{self.class.name} after #{duration.round(2)}s: #{e.message}"
    logger.error e.backtrace.join("\n") if logger.level <= Logger::DEBUG
    raise
  end

  protected

  # Override this method in subclasses to implement job logic
  def execute(*args)
    raise NotImplementedError, "Subclasses must implement the execute method"
  end

  # API client for backend communication
  def api_client
    @api_client ||= BackendApiClient.new
  end

  # Logger instance
  def logger
    PowernodeWorker.application.logger
  end

  # Helper to safely parse JSON
  def safe_parse_json(json_string, default = {})
    return default if json_string.nil? || json_string.empty?
    
    JSON.parse(json_string)
  rescue JSON::ParserError => e
    logger.warn "Failed to parse JSON: #{e.message}, using default: #{default}"
    default
  end

  # Helper to format currency amounts
  def format_currency(cents, currency = 'USD')
    return '$0.00' unless cents&.positive?
    
    dollars = cents.to_f / 100
    "$#{'%.2f' % dollars}"
  end

  # Helper to validate required parameters
  def validate_required_params(params, *required_keys)
    missing_keys = required_keys - params.keys.map(&:to_s)
    
    if missing_keys.any?
      raise ArgumentError, "Missing required parameters: #{missing_keys.join(', ')}"
    end
  end

  # Helper to handle API errors with retry logic
  def with_api_retry(max_attempts: 3, &block)
    attempts = 0
    
    begin
      attempts += 1
      yield
    rescue BackendApiClient::ApiError => e
      if attempts < max_attempts && retryable_error?(e)
        logger.warn "API call failed (attempt #{attempts}/#{max_attempts}): #{e.message}, retrying..."
        sleep(2 ** attempts) # Exponential backoff
        retry
      else
        logger.error "API call failed after #{attempts} attempts: #{e.message}"
        raise
      end
    end
  end

  private

  def retryable_error?(error)
    case error.status
    when 408, 429, 500, 502, 503, 504
      true
    else
      false
    end
  end
  
  protected
  
  def log_job_start(args)
    Sidekiq.logger.info "#{self.class.name} started with args: #{sanitize_args(args)}"
  end
  
  def log_job_completion(start_time, result)
    duration = ((Time.current - start_time) * 1000).round(2)
    Sidekiq.logger.info "#{self.class.name} completed in #{duration}ms"
  end
  
  def log_job_error(error, args)
    Sidekiq.logger.error "#{self.class.name} failed: #{error.message}"
    Sidekiq.logger.error "Args: #{sanitize_args(args)}"
    Sidekiq.logger.error error.backtrace.join("\n")
  end
  
  def sanitize_args(args)
    # Remove sensitive data from logs
    args.map do |arg|
      case arg
      when Hash
        arg.except('password', 'token', 'secret_key', 'credit_card')
      else
        arg
      end
    end
  end
  
  def cleanup
    # Override in subclasses for resource cleanup
  end
  
  # Delegate to worker service
  def delegate_to_worker(job_type, job_data, queue: 'default')
    WorkerJobService.enqueue_billing_job(job_type, job_data.merge(
      originated_from: self.class.name,
      queue: queue
    ))
  end
end
```

#### Billing Job Categories
```ruby
# app/jobs/billing/subscription_renewal_job.rb
class Billing::SubscriptionRenewalJob < BaseJob
  sidekiq_options queue: 'high', retry: 5
  
  def execute(args)
    subscription_id = args['subscription_id']
    retry_attempt = args['retry_attempt'] || 0
    
    subscription = Subscription.find(subscription_id)
    
    # Delegate complex renewal logic to worker service
    delegate_to_worker('subscription_renewal', {
      subscription_id: subscription_id,
      retry_attempt: retry_attempt,
      scheduled_at: Time.current.iso8601
    })
    
    { subscription_id: subscription_id, delegated_to_worker: true }
  rescue ActiveRecord::RecordNotFound
    Sidekiq.logger.error "Subscription not found: #{subscription_id}"
    { error: "Subscription not found", subscription_id: subscription_id }
  end
end

# app/jobs/billing/dunning_process_job.rb
class Billing::DunningProcessJob < BaseJob
  sidekiq_options queue: 'high', retry: 3
  
  def execute(args)
    subscription_id = args['subscription_id']
    dunning_stage = args['dunning_stage'] || 1
    
    subscription = Subscription.find(subscription_id)
    
    # Check if subscription is still eligible for dunning
    unless subscription.past_due?
      return { skipped: true, reason: "Subscription no longer past due" }
    end
    
    # Delegate to worker service for dunning process
    delegate_to_worker('dunning_process', {
      subscription_id: subscription_id,
      dunning_stage: dunning_stage,
      initiated_at: Time.current.iso8601
    })
    
    { subscription_id: subscription_id, dunning_stage: dunning_stage }
  end
end

# app/jobs/billing/payment_retry_job.rb  
class Billing::PaymentRetryJob < BaseJob
  sidekiq_options queue: 'high', retry: 2
  
  def execute(args)
    payment_id = args['payment_id']
    retry_attempt = args['retry_attempt'] || 1
    
    payment = Payment.find(payment_id)
    
    # Check retry eligibility
    if payment.succeeded? || retry_attempt > 3
      return { skipped: true, reason: "Payment succeeded or max retries exceeded" }
    end
    
    # Delegate to worker service
    delegate_to_worker('payment_retry', {
      payment_id: payment_id,
      retry_attempt: retry_attempt,
      initiated_at: Time.current.iso8601
    })
    
    { payment_id: payment_id, retry_attempt: retry_attempt }
  end
end
```

#### API-Only Communication Pattern (CRITICAL)
**MANDATORY**: Workers must use API client for all backend communication, never direct database access.

```ruby
# app/services/backend_api_client.rb - Discovered platform pattern
class BackendApiClient
  include Singleton
  
  BASE_URL = ENV.fetch('BACKEND_API_URL', 'http://localhost:3000/api/v1')
  
  class ApiError < StandardError
    attr_reader :status, :response_body
    
    def initialize(message, status = nil, response_body = nil)
      super(message)
      @status = status
      @response_body = response_body
    end
  end
  
  def initialize
    @token = ENV.fetch('WORKER_TOKEN')
    @timeout = 30
  end
  
  # Standard REST operations
  def get(path)
    make_request(:get, path)
  end
  
  def post(path, data)
    make_request(:post, path, data)
  end
  
  def put(path, data)
    make_request(:put, path, data)
  end
  
  def delete(path)
    make_request(:delete, path)
  end
  
  # Subscription-specific methods
  def renew_subscription(subscription_id)
    post("/subscriptions/#{subscription_id}/renew", {})
  end
  
  def cancel_subscription(subscription_id, reason)
    post("/subscriptions/#{subscription_id}/cancel", { reason: reason })
  end
  
  def process_payment(payment_data)
    post('/payments', payment_data)
  end
  
  def send_notification(notification_data)
    post('/notifications', notification_data)
  end
  
  private
  
  def make_request(method, path, data = nil)
    url = "#{BASE_URL}#{path}"
    
    options = {
      headers: headers,
      timeout: @timeout,
      open_timeout: 10
    }
    
    options[:body] = data.to_json if data && (method == :post || method == :put)
    
    response = HTTParty.send(method, url, options)
    
    handle_response(response)
  rescue Net::TimeoutError => e
    raise ApiError.new("Request timeout: #{e.message}", 408)
  rescue StandardError => e
    raise ApiError.new("Request failed: #{e.message}")
  end
  
  def handle_response(response)
    case response.code
    when 200..299
      response.parsed_response
    when 400..499
      error_message = response.parsed_response&.dig('error') || 'Client error'
      raise ApiError.new(error_message, response.code, response.body)
    when 500..599
      error_message = response.parsed_response&.dig('error') || 'Server error'
      raise ApiError.new(error_message, response.code, response.body)
    else
      raise ApiError.new("Unexpected response: #{response.code}", response.code, response.body)
    end
  end
  
  def headers
    {
      'Content-Type' => 'application/json',
      'Authorization' => "Bearer #{@token}",
      'User-Agent' => 'Powernode-Worker/1.0'
    }
  end
end
```

#### Standard Job Implementation Pattern
```ruby
# Example: Subscription renewal job using API-only pattern
class SubscriptionRenewalJob < BaseJob
  sidekiq_options queue: 'billing', retry: 5
  
  def execute(subscription_id)
    validate_required_params({ 'subscription_id' => subscription_id }, 'subscription_id')
    
    logger.info "Processing subscription renewal for: #{subscription_id}"
    
    # Use API client - NO direct database access
    with_api_retry(max_attempts: 3) do
      result = api_client.renew_subscription(subscription_id)
      
      if result['success']
        logger.info "Successfully renewed subscription: #{subscription_id}"
        
        # Send notification via API
        api_client.send_notification({
          type: 'subscription_renewed',
          subscription_id: subscription_id,
          amount: result.dig('data', 'amount')
        })
      else
        logger.error "Failed to renew subscription: #{result['error']}"
        raise StandardError, result['error']
      end
    end
  end
end
```

**CRITICAL RULES** for worker jobs:
1. **NO ActiveRecord models**: Never `require` or use Rails models directly
2. **API-only communication**: All data access through `BackendApiClient`
3. **Inherit from BaseJob**: Never inherit from `ApplicationJob` 
4. **Use execute method**: Never override `perform`, always use `execute`
5. **Environment isolation**: Workers run independently of main Rails app

### 3. Scheduled Job Management (MANDATORY)

#### Scheduler Jobs
```ruby
# app/jobs/billing/subscription_renewal_scheduler_job.rb
class Billing::SubscriptionRenewalSchedulerJob < BaseJob
  sidekiq_options queue: 'high', retry: 1
  
  def execute(*args)
    # Find subscriptions due for renewal
    due_subscriptions = Subscription.joins(:plan)
                                  .renewable
                                  .where('next_billing_date <= ?', Time.current)
                                  .limit(1000) # Process in batches
    
    scheduled_count = 0
    
    due_subscriptions.find_each do |subscription|
      # Schedule individual renewal job
      Billing::SubscriptionRenewalJob.perform_async({
        'subscription_id' => subscription.id,
        'scheduled_by' => 'renewal_scheduler'
      })
      
      scheduled_count += 1
      
      # Update next billing date to prevent duplicate processing
      subscription.update_column(:last_renewal_check, Time.current)
    end
    
    Sidekiq.logger.info "Scheduled #{scheduled_count} subscription renewals"
    
    { scheduled_renewals: scheduled_count, processed_at: Time.current.iso8601 }
  end
end

# app/jobs/billing/dunning_process_scheduler_job.rb
class Billing::DunningProcessSchedulerJob < BaseJob
  sidekiq_options queue: 'default', retry: 1
  
  def execute(*args)
    # Find subscriptions in dunning process
    past_due_subscriptions = Subscription.past_due
                                        .where('last_dunning_date IS NULL OR last_dunning_date < ?', 1.day.ago)
                                        .limit(500)
    
    scheduled_count = 0
    
    past_due_subscriptions.find_each do |subscription|
      # Determine next dunning stage
      next_stage = calculate_dunning_stage(subscription)
      
      if next_stage
        Billing::DunningProcessJob.perform_async({
          'subscription_id' => subscription.id,
          'dunning_stage' => next_stage,
          'scheduled_by' => 'dunning_scheduler'
        })
        
        scheduled_count += 1
      end
    end
    
    { scheduled_dunning_processes: scheduled_count }
  end
  
  private
  
  def calculate_dunning_stage(subscription)
    days_past_due = (Time.current - subscription.became_past_due_at).to_i / 1.day
    current_stage = subscription.dunning_stage || 0
    
    case days_past_due
    when 1..2
      current_stage < 1 ? 1 : nil
    when 3..6  
      current_stage < 2 ? 2 : nil
    when 7..13
      current_stage < 3 ? 3 : nil
    when 14..20
      current_stage < 4 ? 4 : nil
    when 21..29
      current_stage < 5 ? 5 : nil
    when 30..Float::INFINITY
      current_stage < 6 ? 6 : nil
    else
      nil
    end
  end
end
```

#### Batch Processing Jobs
```ruby
# app/jobs/billing/billing_cleanup_job.rb
class Billing::BillingCleanupJob < BaseJob
  sidekiq_options queue: 'low', retry: 1
  
  def execute(*args)
    cleanup_results = {}
    
    # Cleanup old payment intents
    cleanup_results[:payment_intents] = cleanup_old_payment_intents
    
    # Archive old invoices
    cleanup_results[:invoices] = archive_old_invoices
    
    # Remove expired blacklisted tokens
    cleanup_results[:blacklisted_tokens] = cleanup_blacklisted_tokens
    
    # Cleanup audit logs older than retention period
    cleanup_results[:audit_logs] = cleanup_old_audit_logs
    
    Sidekiq.logger.info "Billing cleanup completed: #{cleanup_results}"
    cleanup_results
  end
  
  private
  
  def cleanup_old_payment_intents
    # Remove payment intents older than 90 days
    count = PaymentIntent.where('created_at < ?', 90.days.ago).delete_all
    Sidekiq.logger.info "Cleaned up #{count} old payment intents"
    count
  end
  
  def archive_old_invoices
    # Archive invoices older than 2 years
    old_invoices = Invoice.where('created_at < ?', 2.years.ago).limit(1000)
    
    archived_count = 0
    old_invoices.find_each do |invoice|
      # Delegate archival to worker service
      delegate_to_worker('archive_invoice', {
        invoice_id: invoice.id,
        archive_reason: 'age_retention'
      }, queue: 'batch')
      
      archived_count += 1
    end
    
    archived_count
  end
  
  def cleanup_blacklisted_tokens
    count = BlacklistedToken.where('expires_at < ?', Time.current).delete_all
    count
  end
  
  def cleanup_old_audit_logs
    # Keep audit logs for 7 years for compliance
    retention_date = 7.years.ago
    count = AuditLog.where('created_at < ?', retention_date).delete_all
    count
  end
end
```

### 4. Job Monitoring and Metrics (MANDATORY)

#### Job Metrics Middleware
```ruby
# app/middleware/job_metrics_middleware.rb
class JobMetricsMiddleware
  def call(job, queue)
    job_class = job['class']
    start_time = Time.current
    
    # Increment job started counter
    increment_counter("sidekiq.jobs.started", tags: { job_class: job_class, queue: queue })
    
    begin
      yield
      
      # Record successful completion
      duration = Time.current - start_time
      record_histogram("sidekiq.jobs.duration", duration, tags: { job_class: job_class, queue: queue })
      increment_counter("sidekiq.jobs.completed", tags: { job_class: job_class, queue: queue })
      
    rescue StandardError => e
      # Record job failure
      increment_counter("sidekiq.jobs.failed", tags: { job_class: job_class, queue: queue, error: e.class.name })
      raise e
    end
  end
  
  private
  
  def increment_counter(metric_name, tags: {})
    # Send metrics to your monitoring system (DataDog, New Relic, etc.)
    Rails.logger.info "METRIC: #{metric_name} #{tags.inspect}"
    
    # Example: DataDog integration
    # Datadog::Statsd.increment(metric_name, tags: tags.map { |k, v| "#{k}:#{v}" })
  end
  
  def record_histogram(metric_name, value, tags: {})
    Rails.logger.info "HISTOGRAM: #{metric_name} #{value} #{tags.inspect}"
    
    # Example: DataDog integration  
    # Datadog::Statsd.histogram(metric_name, value, tags: tags.map { |k, v| "#{k}:#{v}" })
  end
end

# app/middleware/job_audit_middleware.rb
class JobAuditMiddleware
  def call(job, queue)
    job_execution = JobExecution.create!(
      job_class: job['class'],
      job_id: job['jid'],
      queue: queue,
      args: sanitize_args(job['args']),
      started_at: Time.current,
      status: 'running'
    )
    
    begin
      result = yield
      
      job_execution.update!(
        completed_at: Time.current,
        status: 'completed',
        result: result.is_a?(Hash) ? result : { success: true }
      )
      
      result
    rescue StandardError => e
      job_execution.update!(
        completed_at: Time.current,
        status: 'failed',
        error_message: e.message,
        error_backtrace: e.backtrace&.first(10)
      )
      
      raise e
    end
  end
  
  private
  
  def sanitize_args(args)
    # Remove sensitive information from job arguments
    return args unless args.is_a?(Array)
    
    args.map do |arg|
      if arg.is_a?(Hash)
        arg.except('password', 'token', 'secret_key', 'api_key', 'credit_card_number')
      else
        arg
      end
    end
  end
end
```

#### Job Performance Monitoring
```ruby
# app/services/job_performance_monitor.rb
class JobPerformanceMonitor
  def self.report
    {
      queue_stats: queue_statistics,
      job_stats: job_statistics,
      worker_stats: worker_statistics,
      alerts: performance_alerts
    }
  end
  
  def self.queue_statistics
    stats = Sidekiq::Stats.new
    
    {
      processed: stats.processed,
      failed: stats.failed,
      busy: stats.workers_size,
      queues: stats.queues,
      retries: stats.retry_size,
      dead: stats.dead_size,
      scheduled: stats.scheduled_size
    }
  end
  
  def self.job_statistics
    # Get job statistics from the last 24 hours
    recent_executions = JobExecution.where('started_at > ?', 24.hours.ago)
    
    {
      total_jobs: recent_executions.count,
      successful_jobs: recent_executions.where(status: 'completed').count,
      failed_jobs: recent_executions.where(status: 'failed').count,
      average_duration: recent_executions.where.not(completed_at: nil)
                                         .average('EXTRACT(EPOCH FROM (completed_at - started_at))'),
      slowest_jobs: recent_executions.where.not(completed_at: nil)
                                    .order('(completed_at - started_at) DESC')
                                    .limit(10)
                                    .pluck(:job_class, 'EXTRACT(EPOCH FROM (completed_at - started_at))')
    }
  end
  
  def self.worker_statistics
    # Worker service integration statistics
    {
      worker_jobs_delegated: WorkerJobDelegation.where('created_at > ?', 24.hours.ago).count,
      worker_success_rate: calculate_worker_success_rate,
      average_worker_response_time: calculate_average_worker_response_time
    }
  end
  
  def self.performance_alerts
    alerts = []
    
    # Check for high failure rates
    failure_rate = failed_job_rate_last_hour
    alerts << "High job failure rate: #{failure_rate.round(2)}%" if failure_rate > 10
    
    # Check for queue buildup
    stats = Sidekiq::Stats.new
    stats.queues.each do |queue_name, queue_size|
      alerts << "Queue #{queue_name} has #{queue_size} jobs" if queue_size > 1000
    end
    
    # Check for slow jobs
    slow_jobs = JobExecution.where('started_at > ? AND completed_at IS NOT NULL', 1.hour.ago)
                           .where('EXTRACT(EPOCH FROM (completed_at - started_at)) > ?', 300) # 5 minutes
    
    if slow_jobs.count > 10
      alerts << "#{slow_jobs.count} slow jobs (>5 minutes) in the last hour"
    end
    
    alerts
  end
  
  private
  
  def self.failed_job_rate_last_hour
    total_jobs = JobExecution.where('started_at > ?', 1.hour.ago).count
    failed_jobs = JobExecution.where('started_at > ?', 1.hour.ago).where(status: 'failed').count
    
    return 0 if total_jobs == 0
    (failed_jobs.to_f / total_jobs * 100)
  end
  
  def self.calculate_worker_success_rate
    delegations = WorkerJobDelegation.where('created_at > ?', 24.hours.ago)
    return 100 if delegations.count == 0
    
    successful = delegations.where(status: 'completed').count
    (successful.to_f / delegations.count * 100).round(2)
  end
  
  def self.calculate_average_worker_response_time
    completed_delegations = WorkerJobDelegation.where('created_at > ?', 24.hours.ago)
                                              .where.not(completed_at: nil)
    
    return 0 if completed_delegations.count == 0
    
    completed_delegations.average('EXTRACT(EPOCH FROM (completed_at - created_at))') || 0
  end
end
```

### 5. Worker Service Integration (MANDATORY)

#### Worker Job Delegation Service
```ruby
# app/services/worker_job_service.rb
class WorkerJobService
  class WorkerServiceError < StandardError; end
  
  API_TIMEOUT = 30.seconds
  MAX_RETRIES = 3
  
  def self.enqueue_billing_job(job_type, job_data, queue: 'default')
    new.enqueue_job('billing', job_type, job_data, queue)
  end
  
  def self.enqueue_notification_job(job_type, job_data, queue: 'default')
    new.enqueue_job('notifications', job_type, job_data, queue)
  end
  
  def self.enqueue_analytics_job(job_type, job_data, queue: 'default')
    new.enqueue_job('analytics', job_type, job_data, queue)
  end
  
  def self.cancel_billing_job(job_type, criteria = {})
    new.cancel_job('billing', job_type, criteria)
  end
  
  def initialize
    @worker_api_client = BackendApiClient.new(
      base_url: ENV['WORKER_API_URL'],
      token: ENV['WORKER_API_TOKEN'],
      timeout: API_TIMEOUT
    )
  end
  
  def enqueue_job(category, job_type, job_data, queue = 'default')
    delegation_record = create_delegation_record(category, job_type, job_data, queue)
    
    begin
      response = @worker_api_client.post('/jobs', {
        job_category: category,
        job_type: job_type,
        job_data: job_data.merge(delegation_id: delegation_record.id),
        queue: queue,
        priority: calculate_priority(job_type),
        retry_attempts: MAX_RETRIES,
        enqueued_by: 'backend_api',
        enqueued_at: Time.current.iso8601
      })
      
      if response.success?
        delegation_record.update!(
          worker_job_id: response.data['job_id'],
          status: 'enqueued',
          enqueued_at: Time.current
        )
        
        Rails.logger.info "Successfully enqueued #{job_type} job: #{response.data['job_id']}"
        response.data
      else
        delegation_record.update!(status: 'failed', error_message: response.error)
        raise WorkerServiceError, "Failed to enqueue job: #{response.error}"
      end
      
    rescue StandardError => e
      delegation_record.update!(status: 'failed', error_message: e.message)
      Rails.logger.error "Worker service error for #{job_type}: #{e.message}"
      raise WorkerServiceError, e.message
    end
  end
  
  def cancel_job(category, job_type, criteria)
    begin
      response = @worker_api_client.delete('/jobs/cancel', {
        job_category: category,
        job_type: job_type,
        criteria: criteria
      })
      
      if response.success?
        # Update local delegation records
        WorkerJobDelegation.where(
          job_category: category,
          job_type: job_type,
          status: ['pending', 'enqueued']
        ).update_all(
          status: 'cancelled',
          cancelled_at: Time.current
        )
        
        Rails.logger.info "Successfully cancelled #{job_type} jobs matching #{criteria}"
        response.data
      else
        raise WorkerServiceError, "Failed to cancel jobs: #{response.error}"
      end
      
    rescue StandardError => e
      Rails.logger.error "Worker job cancellation error: #{e.message}"
      raise WorkerServiceError, e.message
    end
  end
  
  def get_job_status(worker_job_id)
    begin
      response = @worker_api_client.get("/jobs/#{worker_job_id}/status")
      
      if response.success?
        # Update local delegation record
        delegation = WorkerJobDelegation.find_by(worker_job_id: worker_job_id)
        if delegation
          delegation.update!(
            status: response.data['status'],
            completed_at: response.data['completed_at'] ? Time.parse(response.data['completed_at']) : nil,
            result: response.data['result']
          )
        end
        
        response.data
      else
        raise WorkerServiceError, "Failed to get job status: #{response.error}"
      end
      
    rescue StandardError => e
      Rails.logger.error "Worker job status check error: #{e.message}"
      raise WorkerServiceError, e.message
    end
  end
  
  private
  
  def create_delegation_record(category, job_type, job_data, queue)
    WorkerJobDelegation.create!(
      job_category: category,
      job_type: job_type,
      job_data: job_data,
      queue: queue,
      status: 'pending',
      created_at: Time.current
    )
  end
  
  def calculate_priority(job_type)
    case job_type
    when /renewal/, /payment_failed/, /dunning/
      'high'
    when /notification/, /email/
      'default'
    when /analytics/, /cleanup/, /archive/
      'low'
    else
      'default'
    end
  end
end

# app/models/worker_job_delegation.rb
class WorkerJobDelegation < ApplicationRecord
  validates :job_category, presence: true
  validates :job_type, presence: true
  validates :status, inclusion: { in: %w[pending enqueued running completed failed cancelled] }
  
  scope :pending, -> { where(status: 'pending') }
  scope :running, -> { where(status: 'running') }
  scope :completed, -> { where(status: 'completed') }
  scope :failed, -> { where(status: 'failed') }
  
  def duration
    return nil unless completed_at && enqueued_at
    completed_at - enqueued_at
  end
  
  def success?
    status == 'completed'
  end
end
```

### 6. Error Handling and Retry Logic (MANDATORY)

#### Job Retry Strategies
```ruby
# app/jobs/concerns/retry_strategies.rb
module RetryStrategies
  extend ActiveSupport::Concern
  
  included do
    # Custom retry logic based on error type
    sidekiq_retry_in do |count, exception|
      case exception
      when PaymentGatewayError
        # Exponential backoff for payment errors
        [1.minute, 5.minutes, 15.minutes, 1.hour, 4.hours][count] || 24.hours
      when WorkerServiceError
        # Quick retry for worker service connectivity issues
        [30.seconds, 2.minutes, 10.minutes][count] || :kill
      when ActiveRecord::RecordNotFound
        # Don't retry for missing records
        :kill
      when ActiveRecord::ConnectionTimeoutError
        # Short retry for DB connection issues
        [10.seconds, 30.seconds, 1.minute][count] || 5.minutes
      else
        # Default exponential backoff
        (count ** 2) + 15.seconds
      end
    end
    
    # Death handler for jobs that can't be retried
    sidekiq_retries_exhausted do |job, exception|
      handle_job_failure(job, exception)
    end
  end
  
  class_methods do
    def handle_job_failure(job, exception)
      job_class = job['class']
      job_args = job['args']
      
      # Log the failure
      Sidekiq.logger.error "Job #{job_class} permanently failed: #{exception.message}"
      
      # Create failure record
      JobFailure.create!(
        job_class: job_class,
        job_args: job_args,
        error_class: exception.class.name,
        error_message: exception.message,
        failed_at: Time.current,
        retry_count: job['retry_count']
      )
      
      # Send alert for critical jobs
      if critical_job?(job_class)
        JobFailureNotificationService.call(
          job_class: job_class,
          job_args: job_args,
          error: exception.message,
          critical: true
        )
      end
      
      # Handle specific failure types
      case job_class
      when 'Billing::SubscriptionRenewalJob'
        handle_renewal_failure(job_args.first)
      when 'Billing::PaymentRetryJob'
        handle_payment_failure(job_args.first)
      end
    end
    
    private
    
    def critical_job?(job_class)
      %w[
        Billing::SubscriptionRenewalJob
        Billing::PaymentRetryJob
        Billing::DunningProcessJob
        SystemHealthCheckJob
      ].include?(job_class)
    end
    
    def handle_renewal_failure(job_args)
      subscription_id = job_args['subscription_id']
      
      # Mark subscription as requiring manual intervention
      subscription = Subscription.find_by(id: subscription_id)
      if subscription
        subscription.update!(
          status: 'renewal_failed',
          requires_manual_intervention: true,
          last_renewal_failure_at: Time.current
        )
        
        # Notify admin team
        AdminNotificationService.call(
          type: 'subscription_renewal_failed',
          subscription_id: subscription_id,
          priority: 'high'
        )
      end
    end
    
    def handle_payment_failure(job_args)
      payment_id = job_args['payment_id']
      
      # Mark payment as permanently failed
      payment = Payment.find_by(id: payment_id)
      if payment
        payment.update!(
          status: 'permanently_failed',
          permanent_failure_at: Time.current
        )
        
        # Start manual dunning process
        WorkerJobService.enqueue_billing_job('manual_dunning_required', {
          payment_id: payment_id,
          subscription_id: payment.subscription_id
        })
      end
    end
  end
end
```

#### Error Notification Middleware
```ruby
# app/middleware/error_notification_middleware.rb
class ErrorNotificationMiddleware
  def call(job, queue)
    yield
  rescue StandardError => e
    # Determine if this error needs immediate notification
    if should_notify_immediately?(e, job)
      send_immediate_error_notification(e, job, queue)
    end
    
    # Re-raise to let Sidekiq handle retry logic
    raise e
  end
  
  private
  
  def should_notify_immediately?(error, job)
    # Notify immediately for critical errors or critical jobs
    critical_errors = [
      PaymentGatewayError,
      WorkerServiceError,
      SecurityError
    ]
    
    critical_jobs = [
      'Billing::SubscriptionRenewalJob',
      'Billing::PaymentRetryJob',
      'SystemHealthCheckJob'
    ]
    
    critical_errors.any? { |err_class| error.is_a?(err_class) } ||
    critical_jobs.include?(job['class'])
  end
  
  def send_immediate_error_notification(error, job, queue)
    JobFailureNotificationService.perform_async({
      'job_class' => job['class'],
      'queue' => queue,
      'error_class' => error.class.name,
      'error_message' => error.message,
      'job_args' => sanitize_job_args(job['args']),
      'occurred_at' => Time.current.iso8601,
      'immediate_notification' => true
    })
  end
  
  def sanitize_job_args(args)
    # Remove sensitive information
    args.deep_dup.tap do |sanitized_args|
      sanitized_args.each do |arg|
        if arg.is_a?(Hash)
          arg.delete('password')
          arg.delete('token')
          arg.delete('api_key')
          arg.delete('secret')
        end
      end
    end
  rescue
    ['<args could not be sanitized>']
  end
end
```

## Development Commands

### Background Job Management
```bash
# Start Sidekiq with configuration
bundle exec sidekiq -C config/sidekiq.yml -e development

# Start Sidekiq web interface
bundle exec sidekiq -C config/sidekiq.yml -e development &
open http://localhost:4567/sidekiq

# Monitor job queues
bundle exec sidekiq-cli stats
bundle exec sidekiq-cli busy

# Test job execution
rails console
> Billing::SubscriptionRenewalJob.perform_async({'subscription_id' => '123'})
> JobPerformanceMonitor.report

# Clear queues (development only)
Sidekiq::Queue.new('critical').clear
Sidekiq::Queue.new('high').clear
Sidekiq::RetrySet.new.clear
Sidekiq::DeadSet.new.clear
```

### Job Testing and Debugging
```bash
# Run job-related tests
bundle exec rspec spec/jobs/
bundle exec rspec spec/services/worker_job_service_spec.rb

# Test worker service integration
curl -X POST http://localhost:4567/jobs \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $WORKER_TOKEN" \
  -d '{"job_type": "test", "job_data": {}}'

# Monitor job performance
rails runner "puts JobPerformanceMonitor.report.to_yaml"
```

## Integration Points

### Background Job Engineer Coordinates With:
- **Billing Engine Developer**: Automated billing processes, subscription lifecycles
- **Payment Integration Specialist**: Payment retry mechanisms, webhook processing
- **Rails Architect**: Job middleware configuration, error handling
- **Notification Engineer**: Email delivery, notification queuing
- **DevOps Engineer**: Queue monitoring, performance optimization

## Quick Reference

### Job Categories and Queues
- **critical**: System health, security alerts
- **high**: Billing, payments, renewals, dunning
- **default**: Notifications, regular processing
- **low**: Cleanup, analytics, archival
- **batch**: Large batch operations

### Standard Job Template (Platform Pattern)
```ruby
class SampleJob < BaseJob
  sidekiq_options queue: 'default', retry: 3
  
  def execute(resource_id, options = {})
    # 1. Validate required parameters
    validate_required_params({ 'resource_id' => resource_id }, 'resource_id')
    
    logger.info "Processing resource: #{resource_id}"
    
    # 2. Use API client for all data access
    with_api_retry(max_attempts: 3) do
      result = api_client.post("/resources/#{resource_id}/process", options)
      
      if result['success']
        logger.info "Successfully processed resource: #{resource_id}"
        
        # 3. Send notifications via API
        api_client.send_notification({
          type: 'resource_processed',
          resource_id: resource_id,
          processed_at: Time.current.iso8601
        })
        
        result['data']
      else
        raise StandardError, result['error']
      end
    end
  end
end
```

### Pattern Validation Commands
```bash
# Ensure BaseJob inheritance (should be > 0)
grep -r "< BaseJob" worker/app/jobs/ | wc -l

# Find forbidden ApplicationJob inheritance (should be empty)
grep -r "< ApplicationJob" worker/app/jobs/

# Find forbidden ActiveRecord usage (should be empty)
grep -r "ActiveRecord" worker/app/ | grep -v comments

# Find jobs using execute method (should match BaseJob count)
grep -r "def execute" worker/app/jobs/ | wc -l

# Find forbidden perform method overrides (should be empty)
grep -r "def perform" worker/app/jobs/ | grep -v BaseJob
```

### Worker Service Integration
```ruby
# Enqueue billing job
WorkerJobService.enqueue_billing_job('subscription_renewal', {
  subscription_id: subscription.id,
  scheduled_for: Time.current.iso8601
})

# Cancel scheduled jobs
WorkerJobService.cancel_billing_job('subscription_renewal', {
  subscription_id: subscription.id
})

# Check job status
WorkerJobService.new.get_job_status(worker_job_id)
```

**ALWAYS REFERENCE ../TODO.md FOR CURRENT TASKS AND PRIORITIES**
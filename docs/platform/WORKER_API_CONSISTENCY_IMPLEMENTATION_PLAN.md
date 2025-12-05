# Worker-to-System API Consistency Audit and Fix Plan

## Executive Summary

This plan addresses three categories of worker-to-backend API inconsistencies in the Powernode platform:

1. **4 Jobs with ActiveRecord Violations** - Jobs directly accessing database models instead of using API calls
2. **5 Missing Worker Jobs** - Jobs referenced in backend but not implemented in worker
3. **7 Missing WorkerJobService Methods** - Backend methods calling non-existent service endpoints

## Architecture Context

### Worker Design Principles
- Worker is a **standalone Sidekiq service** with NO direct database access
- All communication with backend via `BackendApiClient` HTTP calls
- Jobs inherit from `BaseJob`, implementing `execute()` method (never `perform()`)
- Uses `api_client` helper (not `backend_api_client`)

### Key Patterns from Existing Code

**BaseJob Pattern:**
```ruby
class SomeJob < BaseJob
  sidekiq_options queue: 'some_queue', retry: 3
  
  def execute(param1, param2)
    # Use api_client for all backend calls
    response = api_client.get("/api/v1/endpoint/#{param1}")
    # Response is a hash - access via response['key']
    if response['success']
      # Process
    end
  end
end
```

**BackendApiClient Response:**
- Returns Hash (not object with methods)
- Access via `response['key']`, NOT `response.key` or `response.success`

---

## Phase 1: Fix ActiveRecord Violations (Priority: CRITICAL)

### 1.1 AiMonitoringHealthCheckJob - Quick Fix

**File:** `/home/rett/Drive/Projects/powernode-platform/worker/app/jobs/ai_monitoring_health_check_job.rb`

**Current Issues:**
- Line 11: Uses `backend_api_client` instead of `api_client`
- Line 15: Uses `response.success` but API returns hash (should be `response['success']`)

**Fix Required:**
```ruby
# Change from:
response = backend_api_client.post(...)
if response.success

# To:
response = api_client.post(...)
if response['success']
```

**Estimated Effort:** 15 minutes

---

### 1.2 AiTemplateUpdateJob - Requires Backend Endpoint

**File:** `/home/rett/Drive/Projects/powernode-platform/worker/app/jobs/ai_template_update_job.rb`

**Current Violations:**
- Line 7: `AiWorkflowTemplateInstallation.find(installation_id)`
- Line 8: `User.find(user_id)`
- Line 12: `installation.update_to_latest_version!(...)`
- Line 18: `AiWorkflowMarketplaceChannel.broadcast_installation_complete(...)`

**Backend Endpoint Required:**
```
POST /api/v1/internal/template_installations/:id/update
Request: { user_id: uuid, preserve_customizations: boolean }
Response: { success: true, data: { installation: {...}, new_version: string } }
```

**Worker Job Rewrite:**
```ruby
def execute(installation_id, user_id = nil)
  logger.info "Updating template installation: #{installation_id}"
  
  response = with_api_retry do
    api_client.post("/api/v1/internal/template_installations/#{installation_id}/update", {
      user_id: user_id,
      preserve_customizations: true
    })
  end
  
  if response['success']
    data = response['data']
    logger.info "Template update successful: #{data['installation']['template_name']} -> #{data['installation']['template_version']}"
    {
      success: true,
      installation_id: installation_id,
      new_version: data['installation']['template_version']
    }
  else
    logger.error "Template update failed: #{installation_id} - #{response['error']}"
    { success: false, installation_id: installation_id, error: response['error'] }
  end
end
```

**Estimated Effort:** 2 hours (including backend endpoint)

---

### 1.3 AiAnalyticsReportJob - Requires Backend Endpoint

**File:** `/home/rett/Drive/Projects/powernode-platform/worker/app/jobs/ai_analytics_report_job.rb`

**Current Violations:**
- Line 7: `AiWorkflow.find(workflow_id)`
- Line 8: `Account.find(account_id)`
- Line 12: References undefined `Mcp::WorkflowAnalyticsEngine`

**Backend Endpoint Required:**
```
POST /api/v1/internal/workflows/:workflow_id/analytics_report
Request: { account_id: uuid, time_range_days: integer, format: string }
Response: { success: true, data: { report_data: string, report_size: integer } }
```

**Worker Job Rewrite:**
```ruby
def execute(workflow_id, account_id, time_range_days = 30, format = 'json')
  logger.info "Generating analytics report for workflow: #{workflow_id}"
  
  response = with_api_retry do
    api_client.post("/api/v1/internal/workflows/#{workflow_id}/analytics_report", {
      account_id: account_id,
      time_range_days: time_range_days,
      format: format
    })
  end
  
  if response['success']
    data = response['data']
    logger.info "Analytics report generated for workflow: #{workflow_id}"
    {
      success: true,
      workflow_id: workflow_id,
      report_size: data['report_size'],
      format: format
    }
  else
    logger.error "Analytics report generation failed: #{response['error']}"
    { success: false, error: response['error'] }
  end
end
```

**Estimated Effort:** 3 hours (including backend service/endpoint)

---

### 1.4 AiErrorPredictionJob - Requires Backend Endpoint

**File:** `/home/rett/Drive/Projects/powernode-platform/worker/app/jobs/ai_error_prediction_job.rb`

**Current Violations:**
- Line 7: `AiWorkflowRun.find_by(run_id: workflow_run_id)`
- Line 16: References undefined `Mcp::AdvancedErrorRecoveryService`
- Line 29: References undefined `AiWorkflowRecoveryChannel`

**Backend Endpoint Required:**
```
POST /api/v1/internal/workflow_runs/:run_id/error_prediction
Request: {}
Response: { 
  success: true, 
  data: { 
    predictions: [{ type: string, confidence: float, recommendation: string }],
    measures_applied: integer 
  }
}
```

**Worker Job Rewrite:**
```ruby
def execute(workflow_run_id)
  logger.info "Running error prediction for workflow run: #{workflow_run_id}"
  
  response = with_api_retry do
    api_client.post("/api/v1/internal/workflow_runs/#{workflow_run_id}/error_prediction", {})
  end
  
  unless response['success']
    logger.error "Workflow run not found or error prediction failed: #{workflow_run_id}"
    return { success: false, error: response['error'] || 'Error prediction failed' }
  end
  
  data = response['data']
  predictions = data['predictions'] || []
  
  if predictions.any?
    logger.info "Found #{predictions.size} potential errors for run: #{workflow_run_id}"
    {
      success: true,
      workflow_run_id: workflow_run_id,
      predictions_found: predictions.size,
      measures_applied: data['measures_applied']
    }
  else
    logger.info "No potential errors detected for run: #{workflow_run_id}"
    { success: true, workflow_run_id: workflow_run_id, predictions_found: 0 }
  end
end
```

**Estimated Effort:** 4 hours (complex service logic in backend)

---

## Phase 2: Implement Missing Worker Jobs (Priority: HIGH)

### 2.1 WebhookDeliveryJob

**Called From:**
- `server/app/services/mcp_broadcast_service.rb:283` - `WebhookDeliveryJob.perform_async(webhook_url, message.to_json)`
- `server/app/models/app_webhook.rb:87` - `WebhookDeliveryJob.perform_async(delivery.id)`

**File to Create:** `/home/rett/Drive/Projects/powernode-platform/worker/app/jobs/webhooks/webhook_delivery_job.rb`

**Implementation:**
```ruby
# frozen_string_literal: true

require_relative 'base_webhook_job'

module Webhooks
  class WebhookDeliveryJob < BaseWebhookJob
    sidekiq_options queue: 'webhooks', retry: 5

    def execute(delivery_id_or_url, payload = nil)
      if payload
        # Direct URL delivery (from mcp_broadcast_service)
        deliver_to_url(delivery_id_or_url, payload)
      else
        # AppWebhookDelivery record ID
        deliver_webhook_delivery(delivery_id_or_url)
      end
    end

    private

    def deliver_to_url(url, payload)
      logger.info "Delivering webhook to URL: #{url}"
      
      response = make_http_request(url, 
        method: :post, 
        body: payload,
        headers: { 'Content-Type' => 'application/json' }
      )
      
      { success: response.code.to_i.between?(200, 299), status_code: response.code }
    end

    def deliver_webhook_delivery(delivery_id)
      # Get delivery details from backend
      delivery = with_api_retry do
        api_client.get("/api/v1/internal/webhook_deliveries/#{delivery_id}")
      end
      
      return unless delivery && delivery['success']
      
      delivery_data = delivery['data']
      webhook_data = delivery_data['webhook']
      
      logger.info "Processing webhook delivery #{delivery_id} to #{webhook_data['url']}"
      
      start_time = Time.current
      begin
        response = make_http_request(
          webhook_data['url'],
          method: webhook_data['http_method'].downcase.to_sym,
          body: delivery_data['request_body'],
          headers: build_headers(webhook_data),
          timeout: webhook_data['timeout_seconds'] || 30
        )
        
        response_time = ((Time.current - start_time) * 1000).to_i
        
        if response.code.to_i.between?(200, 299)
          mark_delivered(delivery_id, response.code.to_i, response_time, response.body)
        else
          mark_failed(delivery_id, "HTTP #{response.code}", response.code.to_i, response_time)
        end
        
      rescue StandardError => e
        response_time = ((Time.current - start_time) * 1000).to_i
        mark_failed(delivery_id, e.message, nil, response_time)
        raise if retryable_error?(e)
      end
    end
    
    def build_headers(webhook_data)
      headers = webhook_data['headers'] || {}
      headers['Content-Type'] = webhook_data['content_type'] || 'application/json'
      headers['X-Webhook-Signature'] = generate_signature(webhook_data['secret_token'], webhook_data['request_body']) if webhook_data['secret_token']
      headers
    end
    
    def generate_signature(secret, payload)
      OpenSSL::HMAC.hexdigest('sha256', secret, payload)
    end
    
    def mark_delivered(delivery_id, status_code, response_time_ms, response_body)
      api_client.patch("/api/v1/internal/webhook_deliveries/#{delivery_id}", {
        status: 'delivered',
        status_code: status_code,
        response_time_ms: response_time_ms,
        response_body: response_body&.truncate(10000),
        delivered_at: Time.current.iso8601
      })
    end
    
    def mark_failed(delivery_id, error_message, status_code, response_time_ms)
      api_client.patch("/api/v1/internal/webhook_deliveries/#{delivery_id}", {
        status: 'failed',
        status_code: status_code,
        response_time_ms: response_time_ms,
        error_message: error_message
      })
    end
    
    def make_http_request(url, method:, body: nil, headers: {}, timeout: 30)
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.read_timeout = timeout
      http.open_timeout = 10
      
      request_class = case method
        when :post then Net::HTTP::Post
        when :put then Net::HTTP::Put
        when :patch then Net::HTTP::Patch
        else Net::HTTP::Post
      end
      
      request = request_class.new(uri)
      headers.each { |k, v| request[k] = v }
      request.body = body if body
      
      http.request(request)
    end
    
    def retryable_error?(error)
      error.is_a?(Net::ReadTimeout) || 
      error.is_a?(Net::OpenTimeout) || 
      error.is_a?(Errno::ECONNREFUSED)
    end
  end
end
```

**Backend Endpoint Required:**
```
GET /api/v1/internal/webhook_deliveries/:id
PATCH /api/v1/internal/webhook_deliveries/:id
```

**Estimated Effort:** 3 hours

---

### 2.2 WebhookRetryJob

**Called From:**
- `server/app/controllers/api/v1/webhooks_controller.rb:212` - `WebhookRetryJob.perform_later(delivery.id)`
- `server/app/models/app_webhook_delivery.rb:137` - `WebhookRetryJob.perform_at(next_retry_at, id)`

**File to Create:** `/home/rett/Drive/Projects/powernode-platform/worker/app/jobs/webhooks/webhook_retry_job.rb`

**Implementation:**
```ruby
# frozen_string_literal: true

require_relative 'base_webhook_job'

module Webhooks
  class WebhookRetryJob < BaseWebhookJob
    sidekiq_options queue: 'webhooks', retry: 3

    def execute(delivery_id)
      logger.info "Retrying webhook delivery: #{delivery_id}"
      
      # Get delivery and check if retryable
      delivery = with_api_retry do
        api_client.get("/api/v1/internal/webhook_deliveries/#{delivery_id}")
      end
      
      unless delivery && delivery['success']
        logger.error "Webhook delivery #{delivery_id} not found"
        return { success: false, error: 'Delivery not found' }
      end
      
      delivery_data = delivery['data']
      
      unless delivery_data['can_retry']
        logger.info "Webhook delivery #{delivery_id} cannot be retried (max attempts reached)"
        return { success: false, error: 'Max retry attempts reached' }
      end
      
      # Increment attempt
      api_client.patch("/api/v1/internal/webhook_deliveries/#{delivery_id}", {
        attempt_number: delivery_data['attempt_number'] + 1
      })
      
      # Delegate to WebhookDeliveryJob
      Webhooks::WebhookDeliveryJob.perform_async(delivery_id)
      
      { success: true, delivery_id: delivery_id, queued: true }
    end
  end
end
```

**Estimated Effort:** 1 hour

---

### 2.3 DunningProcessJob

**Called From:**
- Referenced in `billing_worker_service.rb` (file does not exist, but referenced)
- Pattern suggests: `WorkerJobService.enqueue_job('DunningProcessJob', {...})`

**File to Create:** `/home/rett/Drive/Projects/powernode-platform/worker/app/jobs/billing/dunning_process_job.rb`

**Implementation:**
```ruby
# frozen_string_literal: true

require_relative '../base_job'

module Billing
  class DunningProcessJob < BaseJob
    sidekiq_options queue: 'billing', retry: 3

    def execute(subscription_id, options = {})
      logger.info "Processing dunning for subscription: #{subscription_id}"
      
      # Get subscription details
      subscription = with_api_retry do
        api_client.get("/api/v1/subscriptions/#{subscription_id}")
      end
      
      unless subscription
        logger.error "Subscription #{subscription_id} not found for dunning"
        return { success: false, error: 'Subscription not found' }
      end
      
      dunning_stage = options['dunning_stage'] || determine_dunning_stage(subscription)
      
      case dunning_stage
      when 'soft'
        process_soft_dunning(subscription)
      when 'hard'
        process_hard_dunning(subscription)
      when 'final'
        process_final_dunning(subscription)
      else
        logger.warn "Unknown dunning stage: #{dunning_stage}"
      end
    end

    private

    def determine_dunning_stage(subscription)
      days_overdue = calculate_days_overdue(subscription)
      
      case days_overdue
      when 1..3 then 'soft'
      when 4..7 then 'hard'
      else 'final'
      end
    end
    
    def calculate_days_overdue(subscription)
      period_end = Time.parse(subscription['current_period_end'])
      ((Time.current - period_end) / 1.day).to_i
    end

    def process_soft_dunning(subscription)
      logger.info "Processing soft dunning for #{subscription['id']}"
      
      # Send soft reminder notification
      send_dunning_notification(subscription, 'soft_dunning')
      
      # Schedule next dunning stage
      Billing::DunningProcessJob.perform_in(3.days, subscription['id'], { 'dunning_stage' => 'hard' })
      
      { success: true, stage: 'soft', next_stage_in: '3 days' }
    end

    def process_hard_dunning(subscription)
      logger.info "Processing hard dunning for #{subscription['id']}"
      
      # Send hard reminder notification
      send_dunning_notification(subscription, 'hard_dunning')
      
      # Schedule final dunning stage
      Billing::DunningProcessJob.perform_in(4.days, subscription['id'], { 'dunning_stage' => 'final' })
      
      { success: true, stage: 'hard', next_stage_in: '4 days' }
    end

    def process_final_dunning(subscription)
      logger.info "Processing final dunning for #{subscription['id']}"
      
      # Send final notice
      send_dunning_notification(subscription, 'final_dunning')
      
      # Schedule subscription suspension
      Billing::SubscriptionLifecycleJob.perform_in(
        24.hours,
        'subscription_expired',
        subscription['id'],
        reason: 'dunning_completed'
      )
      
      { success: true, stage: 'final', suspension_scheduled: true }
    end

    def send_dunning_notification(subscription, notification_type)
      notification_params = {
        type: notification_type,
        account_id: subscription['account_id'],
        subscription_id: subscription['id'],
        message: dunning_message(notification_type),
        severity: notification_type == 'final_dunning' ? 'critical' : 'warning'
      }
      
      with_api_retry do
        api_client.post('/api/v1/notifications', notification_params)
      end
    rescue StandardError => e
      logger.error "Failed to send dunning notification: #{e.message}"
    end

    def dunning_message(type)
      case type
      when 'soft_dunning'
        'Payment overdue - please update your payment method'
      when 'hard_dunning'
        'Payment seriously overdue - action required to avoid service interruption'
      when 'final_dunning'
        'Final notice - service will be suspended without immediate payment'
      end
    end
  end
end
```

**Estimated Effort:** 2 hours

---

### 2.4 ReviewNotificationJob

**Called From:**
- `server/app/models/review_notification.rb:158` - `ReviewNotificationJob.perform_async(id)`
- `server/app/models/review_notification.rb:167` - `ReviewNotificationJob.perform_in(delay, id)`

**File to Create:** `/home/rett/Drive/Projects/powernode-platform/worker/app/jobs/notifications/review_notification_job.rb`

**Implementation:**
```ruby
# frozen_string_literal: true

require_relative '../base_job'

module Notifications
  class ReviewNotificationJob < BaseJob
    sidekiq_options queue: 'email', retry: 3

    def execute(notification_id)
      logger.info "Processing review notification: #{notification_id}"
      
      # Get notification details
      notification = with_api_retry do
        api_client.get("/api/v1/internal/review_notifications/#{notification_id}")
      end
      
      unless notification && notification['success']
        logger.error "Review notification #{notification_id} not found"
        return { success: false, error: 'Notification not found' }
      end
      
      notification_data = notification['data']
      
      # Mark as processing
      api_client.patch("/api/v1/internal/review_notifications/#{notification_id}", {
        status: 'processing',
        processed_at: Time.current.iso8601
      })
      
      begin
        # Deliver via configured channels
        delivery_channels = notification_data['delivery_channels'] || ['email']
        
        delivery_channels.each do |channel|
          deliver_via_channel(notification_data, channel)
        end
        
        # Mark as sent
        api_client.patch("/api/v1/internal/review_notifications/#{notification_id}", {
          status: 'sent',
          sent_at: Time.current.iso8601
        })
        
        logger.info "Review notification #{notification_id} sent successfully"
        { success: true, notification_id: notification_id }
        
      rescue StandardError => e
        # Mark as failed
        api_client.patch("/api/v1/internal/review_notifications/#{notification_id}", {
          status: 'failed',
          failed_at: Time.current.iso8601,
          error_message: e.message
        })
        
        raise
      end
    end

    private

    def deliver_via_channel(notification_data, channel)
      case channel
      when 'email'
        deliver_email(notification_data)
      when 'push'
        deliver_push(notification_data)
      when 'in_app'
        deliver_in_app(notification_data)
      else
        logger.warn "Unknown delivery channel: #{channel}"
      end
    end

    def deliver_email(notification_data)
      email_params = {
        template_type: "review_#{notification_data['notification_type']}",
        recipient_id: notification_data['recipient_id'],
        data: notification_data['template_data']
      }
      
      with_api_retry do
        api_client.post('/api/v1/notifications/email', email_params)
      end
    end

    def deliver_push(notification_data)
      # Placeholder for push notification delivery
      logger.info "Push notification delivery not yet implemented"
    end

    def deliver_in_app(notification_data)
      # Create in-app notification via API
      in_app_params = {
        type: 'review_notification',
        account_id: notification_data['recipient_id'],
        title: notification_data.dig('template_data', 'title'),
        message: notification_data.dig('template_data', 'body'),
        data: notification_data['template_data']
      }
      
      with_api_retry do
        api_client.post('/api/v1/notifications', in_app_params)
      end
    end
  end
end
```

**Backend Endpoint Required:**
```
GET /api/v1/internal/review_notifications/:id
PATCH /api/v1/internal/review_notifications/:id
```

**Estimated Effort:** 2 hours

---

### 2.5 AiWebhookDeliveryJob

**Called From:**
- `server/app/models/ai_agent_execution.rb:181,226` - `AiWebhookDeliveryJob.perform_later(id)`

**File to Create:** `/home/rett/Drive/Projects/powernode-platform/worker/app/jobs/ai_webhook_delivery_job.rb`

**Implementation:**
```ruby
# frozen_string_literal: true

require_relative 'base_job'

class AiWebhookDeliveryJob < BaseJob
  include AiJobsConcern
  
  sidekiq_options queue: 'ai_workflows', retry: 3

  MAX_WEBHOOK_ATTEMPTS = 3

  def execute(execution_id)
    logger.info "Delivering AI execution webhook for: #{execution_id}"
    
    # Get execution details
    execution = with_api_retry do
      api_client.get("/api/v1/ai/agent_executions/#{execution_id}")
    end
    
    unless execution && execution['success']
      logger.error "AI agent execution #{execution_id} not found"
      return { success: false, error: 'Execution not found' }
    end
    
    execution_data = execution['data']
    webhook_url = execution_data['webhook_url']
    
    unless webhook_url.present?
      logger.info "No webhook URL configured for execution #{execution_id}"
      return { success: true, skipped: true, reason: 'No webhook URL' }
    end
    
    webhook_attempts = execution_data['webhook_attempts'] || 0
    
    if webhook_attempts >= MAX_WEBHOOK_ATTEMPTS
      logger.warn "Max webhook attempts reached for execution #{execution_id}"
      update_webhook_status(execution_id, 'failed', webhook_attempts)
      return { success: false, error: 'Max attempts exceeded' }
    end
    
    # Build webhook payload
    payload = build_webhook_payload(execution_data)
    
    begin
      response = deliver_webhook(webhook_url, payload)
      
      if response.code.to_i.between?(200, 299)
        update_webhook_status(execution_id, 'success', webhook_attempts + 1)
        logger.info "Webhook delivered successfully for execution #{execution_id}"
        { success: true, status_code: response.code.to_i }
      else
        handle_webhook_failure(execution_id, "HTTP #{response.code}", webhook_attempts + 1)
      end
      
    rescue StandardError => e
      handle_webhook_failure(execution_id, e.message, webhook_attempts + 1)
    end
  end

  private

  def build_webhook_payload(execution_data)
    {
      event: 'ai_execution_completed',
      execution_id: execution_data['execution_id'],
      status: execution_data['status'],
      agent_id: execution_data['ai_agent_id'],
      output_data: execution_data['output_data'],
      error_message: execution_data['error_message'],
      duration_ms: execution_data['duration_ms'],
      tokens_used: execution_data['tokens_used'],
      cost_usd: execution_data['cost_usd'],
      completed_at: execution_data['completed_at'],
      timestamp: Time.current.iso8601
    }.to_json
  end

  def deliver_webhook(url, payload)
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.read_timeout = 30
    http.open_timeout = 10
    
    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request['User-Agent'] = 'Powernode-AI-Webhook/1.0'
    request.body = payload
    
    http.request(request)
  end

  def update_webhook_status(execution_id, status, attempts)
    api_client.patch("/api/v1/ai/agent_executions/#{execution_id}", {
      webhook_status: status,
      webhook_attempts: attempts
    })
  end

  def handle_webhook_failure(execution_id, error, attempts)
    logger.warn "Webhook delivery failed for execution #{execution_id}: #{error}"
    
    update_webhook_status(execution_id, 'failed', attempts)
    
    # Schedule retry if under limit
    if attempts < MAX_WEBHOOK_ATTEMPTS
      retry_delay = (2 ** attempts) * 60 # Exponential backoff: 2, 4, 8 minutes
      AiWebhookDeliveryJob.perform_in(retry_delay, execution_id)
      logger.info "Scheduled webhook retry for execution #{execution_id} in #{retry_delay}s"
    end
    
    { success: false, error: error, attempts: attempts }
  end
end
```

**Estimated Effort:** 2 hours

---

## Phase 3: Add Missing WorkerJobService Methods (Priority: HIGH)

**File to Modify:** `/home/rett/Drive/Projects/powernode-platform/server/app/services/worker_job_service.rb`

### Methods to Add:

```ruby
# Add these class methods to WorkerJobService

# Enqueue billing automation job
def enqueue_billing_automation(subscription_id = nil, delay: 0)
  options = { 'queue' => 'billing' }
  options['at'] = (Time.current + delay).to_f if delay > 0
  
  new.make_worker_request('POST', '/api/v1/jobs', {
    'job_class' => 'Billing::BillingAutomationJob',
    'args' => [subscription_id].compact,
    'options' => options
  })
end

# Enqueue billing scheduler job
def enqueue_billing_scheduler(date, delay: 0)
  options = { 'queue' => 'billing_scheduler' }
  options['at'] = (Time.current + delay).to_f if delay > 0
  
  new.make_worker_request('POST', '/api/v1/jobs', {
    'job_class' => 'Billing::BillingSchedulerJob',
    'args' => [date.to_s],
    'options' => options
  })
end

# Enqueue billing cleanup job
def enqueue_billing_cleanup(delay: 0)
  options = { 'queue' => 'billing' }
  options['at'] = (Time.current + delay).to_f if delay > 0
  
  new.make_worker_request('POST', '/api/v1/jobs', {
    'job_class' => 'Billing::BillingCleanupJob',
    'args' => [],
    'options' => options
  })
end

# Enqueue payment retry job
def enqueue_payment_retry(payment_id, reason, retry_attempt = 1)
  new.make_worker_request('POST', '/api/v1/jobs', {
    'job_class' => 'Billing::PaymentRetryJob',
    'args' => [payment_id, reason, retry_attempt],
    'queue' => 'billing'
  })
end

# Enqueue subscription lifecycle job
def enqueue_subscription_lifecycle(action, subscription_id, **options)
  new.make_worker_request('POST', '/api/v1/jobs', {
    'job_class' => 'Billing::SubscriptionLifecycleJob',
    'args' => [action.to_s, subscription_id, options],
    'queue' => 'subscription_lifecycle'
  })
end

# Enqueue node execution retry job
def enqueue_node_execution_retry(node_execution_id, delay_ms: 0)
  options = { 'queue' => 'ai_workflows' }
  options['at'] = (Time.current + (delay_ms / 1000.0)).to_f if delay_ms > 0
  
  new.make_worker_request('POST', '/api/v1/jobs', {
    'job_class' => 'AiWorkflowNodeExecutionJob',
    'args' => [node_execution_id, { 'is_retry' => true }],
    'options' => options
  })
end

# Generic enqueue job method
def enqueue_job(job_class, args = {})
  new.make_worker_request('POST', '/api/v1/jobs', {
    'job_class' => job_class,
    'args' => [args],
    'queue' => determine_queue_for_job(job_class)
  })
end

private

def determine_queue_for_job(job_class)
  case job_class
  when /Billing|Payment|Subscription/
    'billing'
  when /Webhook/
    'webhooks'
  when /Notification|Email/
    'email'
  when /Ai|Workflow/
    'ai_workflows'
  else
    'default'
  end
end
```

**Estimated Effort:** 1.5 hours

---

## Phase 4: Backend Internal API Endpoints (Priority: HIGH)

### 4.1 Template Installations Controller

**File to Create:** `/home/rett/Drive/Projects/powernode-platform/server/app/controllers/api/v1/internal/template_installations_controller.rb`

```ruby
# frozen_string_literal: true

class Api::V1::Internal::TemplateInstallationsController < Api::V1::Worker::WorkerBaseController
  # POST /api/v1/internal/template_installations/:id/update
  def update
    installation = AiWorkflowTemplateInstallation.find(params[:id])
    user = params[:user_id] ? User.find(params[:user_id]) : installation.installed_by_user
    
    success = installation.update_to_latest_version!(
      user,
      preserve_customizations: params[:preserve_customizations] || true
    )
    
    if success
      # Broadcast update completion
      AiWorkflowMarketplaceChannel.broadcast_installation_complete(
        installation.account,
        installation
      )
      
      render_success(
        data: {
          installation: serialize_installation(installation),
          new_version: installation.template_version
        }
      )
    else
      render_error('Template update failed')
    end
  rescue ActiveRecord::RecordNotFound => e
    render_error(e.message, status: :not_found)
  end

  private

  def serialize_installation(installation)
    {
      id: installation.id,
      installation_id: installation.installation_id,
      template_name: installation.template_name,
      template_version: installation.template_version,
      account_id: installation.account_id
    }
  end
end
```

### 4.2 Workflow Analytics Controller

**File to Create:** `/home/rett/Drive/Projects/powernode-platform/server/app/controllers/api/v1/internal/workflow_analytics_controller.rb`

```ruby
# frozen_string_literal: true

class Api::V1::Internal::WorkflowAnalyticsController < Api::V1::Worker::WorkerBaseController
  # POST /api/v1/internal/workflows/:workflow_id/analytics_report
  def create
    workflow = AiWorkflow.find(params[:workflow_id])
    account = Account.find(params[:account_id])
    
    time_range_days = params[:time_range_days] || 30
    format = params[:format] || 'json'
    
    # Generate analytics report
    analytics_service = AiWorkflowAnalyticsService.new(
      workflow: workflow,
      account: account
    )
    
    report_data = analytics_service.generate_report(
      time_range: time_range_days.days,
      format: format.to_sym
    )
    
    render_success(
      data: {
        report_data: report_data,
        report_size: report_data.to_s.size,
        generated_at: Time.current.iso8601
      }
    )
  rescue ActiveRecord::RecordNotFound => e
    render_error(e.message, status: :not_found)
  end
end
```

### 4.3 Workflow Run Error Prediction Controller

**File to Create:** `/home/rett/Drive/Projects/powernode-platform/server/app/controllers/api/v1/internal/workflow_runs_controller.rb`

```ruby
# frozen_string_literal: true

class Api::V1::Internal::WorkflowRunsController < Api::V1::Worker::WorkerBaseController
  # POST /api/v1/internal/workflow_runs/:run_id/error_prediction
  def error_prediction
    workflow_run = AiWorkflowRun.find_by!(run_id: params[:run_id])
    
    # Run error prediction analysis
    prediction_service = AiWorkflowErrorPredictionService.new(workflow_run: workflow_run)
    predictions = prediction_service.predict_potential_errors
    
    measures_applied = 0
    if predictions.any?
      result = prediction_service.apply_preventive_measures(predictions)
      measures_applied = result[:measures_applied]
      
      # Broadcast predictions
      predictions.each do |prediction|
        AiWorkflowRecoveryChannel.broadcast_error_prediction(workflow_run, prediction)
      end
    end
    
    render_success(
      data: {
        predictions: predictions,
        measures_applied: measures_applied
      }
    )
  rescue ActiveRecord::RecordNotFound
    render_error('Workflow run not found', status: :not_found)
  end
end
```

### 4.4 Webhook Deliveries Controller

**File to Create:** `/home/rett/Drive/Projects/powernode-platform/server/app/controllers/api/v1/internal/webhook_deliveries_controller.rb`

```ruby
# frozen_string_literal: true

class Api::V1::Internal::WebhookDeliveriesController < Api::V1::Worker::WorkerBaseController
  before_action :find_delivery, only: [:show, :update]

  # GET /api/v1/internal/webhook_deliveries/:id
  def show
    render_success(
      data: serialize_delivery(@delivery)
    )
  end

  # PATCH /api/v1/internal/webhook_deliveries/:id
  def update
    if @delivery.update(delivery_params)
      render_success(
        data: serialize_delivery(@delivery)
      )
    else
      render_validation_error(@delivery)
    end
  end

  private

  def find_delivery
    @delivery = AppWebhookDelivery.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_error('Webhook delivery not found', status: :not_found)
  end

  def delivery_params
    params.permit(
      :status, :status_code, :response_time_ms, :response_body,
      :response_headers, :error_message, :delivered_at, :attempt_number
    )
  end

  def serialize_delivery(delivery)
    {
      id: delivery.id,
      delivery_id: delivery.delivery_id,
      event_id: delivery.event_id,
      status: delivery.status,
      attempt_number: delivery.attempt_number,
      request_body: delivery.request_body,
      can_retry: delivery.can_retry?,
      webhook: {
        id: delivery.app_webhook.id,
        url: delivery.app_webhook.url,
        http_method: delivery.app_webhook.http_method,
        content_type: delivery.app_webhook.content_type,
        timeout_seconds: delivery.app_webhook.timeout_seconds,
        secret_token: delivery.app_webhook.secret_token,
        headers: delivery.app_webhook.headers_json
      }
    }
  end
end
```

### 4.5 Review Notifications Controller

**File to Create:** `/home/rett/Drive/Projects/powernode-platform/server/app/controllers/api/v1/internal/review_notifications_controller.rb`

```ruby
# frozen_string_literal: true

class Api::V1::Internal::ReviewNotificationsController < Api::V1::Worker::WorkerBaseController
  before_action :find_notification, only: [:show, :update]

  # GET /api/v1/internal/review_notifications/:id
  def show
    render_success(
      data: serialize_notification(@notification)
    )
  end

  # PATCH /api/v1/internal/review_notifications/:id
  def update
    if @notification.update(notification_params)
      render_success(
        data: serialize_notification(@notification)
      )
    else
      render_validation_error(@notification)
    end
  end

  private

  def find_notification
    @notification = ReviewNotification.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_error('Review notification not found', status: :not_found)
  end

  def notification_params
    params.permit(
      :status, :processed_at, :sent_at, :failed_at, :error_message
    )
  end

  def serialize_notification(notification)
    {
      id: notification.id,
      notification_type: notification.notification_type,
      recipient_id: notification.recipient_id,
      delivery_channels: notification.delivery_channels,
      template_data: notification.template_data,
      priority: notification.priority,
      status: notification.status,
      retry_count: notification.retry_count
    }
  end
end
```

### 4.6 Routes Updates

**File to Modify:** `/home/rett/Drive/Projects/powernode-platform/server/config/routes.rb`

Add within the `namespace :internal` block:
```ruby
namespace :internal do
  # Existing routes...
  
  # Template installations
  resources :template_installations, only: [] do
    member do
      post :update
    end
  end
  
  # Workflow analytics
  resources :workflows, only: [] do
    member do
      post :analytics_report
    end
  end
  
  # Workflow runs
  resources :workflow_runs, only: [], param: :run_id do
    member do
      post :error_prediction
    end
  end
  
  # Webhook deliveries
  resources :webhook_deliveries, only: [:show, :update]
  
  # Review notifications
  resources :review_notifications, only: [:show, :update]
end
```

**Estimated Effort for Phase 4:** 6 hours

---

## Phase 5: Testing Strategy

### 5.1 Worker Job Tests

For each new/modified job, create RSpec tests in `/home/rett/Drive/Projects/powernode-platform/worker/spec/jobs/`:

- `spec/jobs/webhooks/webhook_delivery_job_spec.rb`
- `spec/jobs/webhooks/webhook_retry_job_spec.rb`
- `spec/jobs/billing/dunning_process_job_spec.rb`
- `spec/jobs/notifications/review_notification_job_spec.rb`
- `spec/jobs/ai_webhook_delivery_job_spec.rb`

### 5.2 Backend Controller Tests

For each new controller, create RSpec tests in `/home/rett/Drive/Projects/powernode-platform/server/spec/controllers/api/v1/internal/`:

- `template_installations_controller_spec.rb`
- `workflow_analytics_controller_spec.rb`
- `workflow_runs_controller_spec.rb`
- `webhook_deliveries_controller_spec.rb`
- `review_notifications_controller_spec.rb`

### 5.3 Integration Tests

Create integration tests verifying worker-to-backend communication:

```ruby
# server/spec/integration/worker_api_spec.rb
RSpec.describe 'Worker API Integration' do
  describe 'webhook delivery flow' do
    it 'processes webhook delivery end-to-end'
  end
  
  describe 'billing automation flow' do
    it 'enqueues and processes billing jobs'
  end
end
```

---

## Implementation Schedule

### Week 1: Critical Fixes
| Day | Task | Effort |
|-----|------|--------|
| 1 | Fix AiMonitoringHealthCheckJob | 15 min |
| 1-2 | Fix AiTemplateUpdateJob + backend endpoint | 2 hrs |
| 2-3 | Fix AiAnalyticsReportJob + backend endpoint | 3 hrs |
| 3-4 | Fix AiErrorPredictionJob + backend endpoint | 4 hrs |
| 5 | Add WorkerJobService methods | 1.5 hrs |

### Week 2: Missing Jobs + Endpoints
| Day | Task | Effort |
|-----|------|--------|
| 1 | WebhookDeliveryJob + backend endpoint | 3 hrs |
| 1 | WebhookRetryJob | 1 hr |
| 2 | DunningProcessJob | 2 hrs |
| 2-3 | ReviewNotificationJob + backend endpoint | 2 hrs |
| 3 | AiWebhookDeliveryJob | 2 hrs |
| 4-5 | Routes updates + testing | 4 hrs |

### Week 3: Testing & Validation
| Day | Task | Effort |
|-----|------|--------|
| 1-2 | Worker job unit tests | 4 hrs |
| 2-3 | Backend controller tests | 4 hrs |
| 4-5 | Integration testing + bug fixes | 6 hrs |

---

## Summary

### Files to Create
1. `/home/rett/Drive/Projects/powernode-platform/worker/app/jobs/webhooks/webhook_delivery_job.rb`
2. `/home/rett/Drive/Projects/powernode-platform/worker/app/jobs/webhooks/webhook_retry_job.rb`
3. `/home/rett/Drive/Projects/powernode-platform/worker/app/jobs/billing/dunning_process_job.rb`
4. `/home/rett/Drive/Projects/powernode-platform/worker/app/jobs/notifications/review_notification_job.rb`
5. `/home/rett/Drive/Projects/powernode-platform/worker/app/jobs/ai_webhook_delivery_job.rb`
6. `/home/rett/Drive/Projects/powernode-platform/server/app/controllers/api/v1/internal/template_installations_controller.rb`
7. `/home/rett/Drive/Projects/powernode-platform/server/app/controllers/api/v1/internal/workflow_analytics_controller.rb`
8. `/home/rett/Drive/Projects/powernode-platform/server/app/controllers/api/v1/internal/workflow_runs_controller.rb`
9. `/home/rett/Drive/Projects/powernode-platform/server/app/controllers/api/v1/internal/webhook_deliveries_controller.rb`
10. `/home/rett/Drive/Projects/powernode-platform/server/app/controllers/api/v1/internal/review_notifications_controller.rb`

### Files to Modify
1. `/home/rett/Drive/Projects/powernode-platform/worker/app/jobs/ai_monitoring_health_check_job.rb`
2. `/home/rett/Drive/Projects/powernode-platform/worker/app/jobs/ai_template_update_job.rb`
3. `/home/rett/Drive/Projects/powernode-platform/worker/app/jobs/ai_analytics_report_job.rb`
4. `/home/rett/Drive/Projects/powernode-platform/worker/app/jobs/ai_error_prediction_job.rb`
5. `/home/rett/Drive/Projects/powernode-platform/server/app/services/worker_job_service.rb`
6. `/home/rett/Drive/Projects/powernode-platform/server/config/routes.rb`

### Total Estimated Effort
- Phase 1 (ActiveRecord Fixes): ~9.25 hours
- Phase 2 (Missing Jobs): ~10 hours
- Phase 3 (WorkerJobService Methods): ~1.5 hours
- Phase 4 (Backend Endpoints): ~6 hours
- Phase 5 (Testing): ~14 hours

**Total: ~40.75 hours (~1 week of focused development)**

---

## Critical Files for Implementation

1. **`/home/rett/Drive/Projects/powernode-platform/worker/app/jobs/base_job.rb`** - Core pattern to follow for all jobs
2. **`/home/rett/Drive/Projects/powernode-platform/worker/app/services/backend_api_client.rb`** - API client interface to use
3. **`/home/rett/Drive/Projects/powernode-platform/server/app/services/worker_job_service.rb`** - Service needing new methods
4. **`/home/rett/Drive/Projects/powernode-platform/server/app/controllers/api/v1/worker/worker_base_controller.rb`** - Base controller pattern for internal endpoints
5. **`/home/rett/Drive/Projects/powernode-platform/worker/app/jobs/billing/billing_automation_job.rb`** - Reference implementation for API-only billing jobs

# frozen_string_literal: true

# Background job to check health of AI providers
# Runs every 10 minutes to ensure providers are responsive and functional
class AiProviderHealthCheckJob < BaseJob
  queue_as :ai_workflow_health

  # Health check configuration
  RESPONSE_TIME_WARNING_MS = 5000   # 5 seconds
  RESPONSE_TIME_CRITICAL_MS = 10000 # 10 seconds
  CONSECUTIVE_FAILURE_THRESHOLD = 3

  def execute
    log_info("Starting AI Provider Health Check")

    health_report = {
      timestamp: Time.current.iso8601,
      overall_status: 'healthy',
      providers: {},
      summary: {
        total: 0,
        healthy: 0,
        degraded: 0,
        unhealthy: 0,
        disabled: 0
      }
    }

    begin
      # Fetch all configured providers
      providers = fetch_providers

      health_report[:summary][:total] = providers.size

      # Check each provider
      providers.each do |provider|
        check_provider_health(provider, health_report)
      end

      # Calculate overall status
      calculate_overall_status(health_report)

      # Store health metrics
      store_health_metrics(health_report)

      # Process alerts for unhealthy providers
      process_provider_alerts(health_report)

      # Broadcast status update
      broadcast_health_status(health_report)

      log_info("AI Provider Health Check completed: #{health_report[:overall_status]} " \
               "(#{health_report[:summary][:healthy]}/#{health_report[:summary][:total]} healthy)")
    rescue StandardError => e
      log_error("AI Provider Health Check failed", e)
      health_report[:overall_status] = 'error'
      health_report[:error] = e.message
    end

    health_report
  end

  private

  def fetch_providers
    response = with_api_retry do
      api_client.get('admin/ai_providers', { include_disabled: true })
    end

    response['providers'] || []
  rescue StandardError => e
    log_error("Failed to fetch providers", e)
    []
  end

  def check_provider_health(provider, health_report)
    provider_id = provider['id']
    provider_name = provider['name'] || provider['provider_type']

    # Skip disabled providers but count them
    if provider['status'] == 'disabled' || provider['is_active'] == false
      health_report[:summary][:disabled] += 1
      health_report[:providers][provider_name] = {
        id: provider_id,
        status: 'disabled',
        message: 'Provider is disabled',
        checked_at: Time.current.iso8601
      }
      return
    end

    begin
      # Perform health check via API
      start_time = Time.current
      result = with_api_retry(max_attempts: 1) do
        api_client.post("admin/ai_providers/#{provider_id}/health_check", {
          timeout: 15,
          test_type: 'basic'
        })
      end
      response_time_ms = ((Time.current - start_time) * 1000).round

      # Analyze result
      provider_health = analyze_provider_health(provider, result, response_time_ms)
      health_report[:providers][provider_name] = provider_health

      # Update summary counts
      case provider_health[:status]
      when 'healthy'
        health_report[:summary][:healthy] += 1
      when 'degraded'
        health_report[:summary][:degraded] += 1
      else
        health_report[:summary][:unhealthy] += 1
      end
    rescue StandardError => e
      log_error("Health check failed for provider #{provider_name}", e)

      health_report[:providers][provider_name] = {
        id: provider_id,
        status: 'unhealthy',
        error: e.message,
        response_time_ms: nil,
        checked_at: Time.current.iso8601
      }
      health_report[:summary][:unhealthy] += 1
    end
  end

  def analyze_provider_health(provider, result, response_time_ms)
    status = 'healthy'
    issues = []

    # Check if response indicates healthy
    is_healthy = result['healthy'] || result['success']

    unless is_healthy
      status = 'unhealthy'
      issues << (result['error'] || 'Provider returned unhealthy status')
    end

    # Check response time
    if response_time_ms >= RESPONSE_TIME_CRITICAL_MS
      status = 'unhealthy' if status == 'healthy'
      issues << "Critical response time: #{response_time_ms}ms"
    elsif response_time_ms >= RESPONSE_TIME_WARNING_MS
      status = 'degraded' if status == 'healthy'
      issues << "Slow response time: #{response_time_ms}ms"
    end

    # Check error rate if available
    error_rate = result['error_rate'] || 0
    if error_rate > 10
      status = 'unhealthy' if status == 'healthy'
      issues << "High error rate: #{error_rate}%"
    elsif error_rate > 5
      status = 'degraded' if status == 'healthy'
      issues << "Elevated error rate: #{error_rate}%"
    end

    # Check consecutive failures
    consecutive_failures = result['consecutive_failures'] || 0
    if consecutive_failures >= CONSECUTIVE_FAILURE_THRESHOLD
      status = 'unhealthy'
      issues << "#{consecutive_failures} consecutive failures"
    end

    {
      id: provider['id'],
      status: status,
      healthy: is_healthy,
      response_time_ms: response_time_ms,
      error_rate: error_rate,
      consecutive_failures: consecutive_failures,
      issues: issues,
      capabilities: result['capabilities'] || [],
      rate_limit_remaining: result['rate_limit_remaining'],
      quota_remaining: result['quota_remaining'],
      last_successful_call: result['last_successful_call'],
      checked_at: Time.current.iso8601
    }
  end

  def calculate_overall_status(health_report)
    summary = health_report[:summary]
    active_providers = summary[:total] - summary[:disabled]

    return health_report[:overall_status] = 'healthy' if active_providers.zero?

    unhealthy_percentage = (summary[:unhealthy].to_f / active_providers * 100).round(1)
    degraded_percentage = (summary[:degraded].to_f / active_providers * 100).round(1)

    if unhealthy_percentage >= 50
      health_report[:overall_status] = 'critical'
    elsif unhealthy_percentage > 0 || degraded_percentage >= 50
      health_report[:overall_status] = 'degraded'
    elsif degraded_percentage > 0
      health_report[:overall_status] = 'warning'
    else
      health_report[:overall_status] = 'healthy'
    end
  end

  def store_health_metrics(health_report)
    with_api_retry do
      api_client.post('admin/ai_provider_health_metrics', {
        timestamp: health_report[:timestamp],
        overall_status: health_report[:overall_status],
        summary: health_report[:summary],
        providers: health_report[:providers]
      })
    end
  rescue StandardError => e
    log_error("Failed to store health metrics", e)
  end

  def process_provider_alerts(health_report)
    health_report[:providers].each do |provider_name, provider_health|
      next unless provider_health[:status] == 'unhealthy'

      begin
        with_api_retry do
          api_client.post('admin/system_alerts', {
            alert_type: 'ai_provider_health',
            severity: 'warning',
            category: 'provider_monitoring',
            title: "AI Provider Unhealthy: #{provider_name}",
            message: provider_health[:issues]&.join(', ') || 'Provider health check failed',
            metadata: {
              provider_id: provider_health[:id],
              provider_name: provider_name,
              response_time_ms: provider_health[:response_time_ms],
              error: provider_health[:error]
            }
          })
        end
        log_info("Sent health alert for provider: #{provider_name}")
      rescue StandardError => e
        log_error("Failed to send alert for provider #{provider_name}", e)
      end
    end

    # Send critical alert if overall status is critical
    return unless health_report[:overall_status] == 'critical'

    begin
      with_api_retry do
        api_client.post('admin/system_alerts', {
          alert_type: 'ai_provider_health',
          severity: 'critical',
          category: 'provider_monitoring',
          title: 'Critical: Multiple AI Providers Unhealthy',
          message: "#{health_report[:summary][:unhealthy]} out of #{health_report[:summary][:total]} providers are unhealthy",
          metadata: {
            summary: health_report[:summary],
            unhealthy_providers: health_report[:providers].select { |_, v| v[:status] == 'unhealthy' }.keys
          }
        })
      end
    rescue StandardError => e
      log_error("Failed to send critical health alert", e)
    end
  end

  def broadcast_health_status(health_report)
    begin
      AiWorkflowMonitoringChannel.broadcast_provider_health(health_report)
    rescue StandardError => e
      log_error("Failed to broadcast provider health status", e)
    end
  end
end

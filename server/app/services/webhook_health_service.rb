# frozen_string_literal: true

class WebhookHealthService
  HEALTH_CHECK_TIMEOUT = 30.seconds
  HEALTHY_THRESHOLD = 0.95 # 95% success rate
  MIN_EVENTS_FOR_HEALTH_CHECK = 10

  def initialize(account = nil)
    @account = account
  end

  # Get overall webhook system health
  def overall_health
    endpoints = @account ? @account.webhook_endpoints : WebhookEndpoint.all
    return { status: 'no_webhooks', message: 'No webhook endpoints configured' } if endpoints.empty?

    endpoint_healths = endpoints.map { |endpoint| check_endpoint_health(endpoint) }
    
    healthy_count = endpoint_healths.count { |h| h[:status] == 'healthy' }
    unhealthy_count = endpoint_healths.count { |h| h[:status] == 'unhealthy' }
    warning_count = endpoint_healths.count { |h| h[:status] == 'warning' }

    overall_status = determine_overall_status(healthy_count, unhealthy_count, warning_count, endpoints.count)
    
    {
      status: overall_status,
      summary: {
        total_endpoints: endpoints.count,
        healthy: healthy_count,
        warning: warning_count,
        unhealthy: unhealthy_count
      },
      endpoints: endpoint_healths,
      last_checked: Time.current.iso8601
    }
  end

  # Check health of a specific endpoint
  def check_endpoint_health(endpoint)
    recent_deliveries = endpoint.webhook_deliveries.where('created_at >= ?', 24.hours.ago)
    
    if recent_deliveries.empty?
      return {
        endpoint_id: endpoint.id,
        url: endpoint.url,
        status: 'no_activity',
        message: 'No webhook deliveries in the last 24 hours',
        success_rate: 0,
        total_deliveries: 0,
        successful_deliveries: 0,
        last_delivery: nil
      }
    end

    successful = recent_deliveries.where(status: 'success').count
    total = recent_deliveries.count
    success_rate = (successful.to_f / total * 100).round(2)

    last_delivery = recent_deliveries.order(:created_at).last

    status = determine_endpoint_status(success_rate, total)
    
    {
      endpoint_id: endpoint.id,
      url: endpoint.url,
      status: status,
      message: generate_health_message(status, success_rate, total),
      success_rate: success_rate,
      total_deliveries: total,
      successful_deliveries: successful,
      last_delivery: last_delivery&.created_at&.iso8601,
      last_delivery_status: last_delivery&.status,
      events_subscribed: endpoint.events
    }
  end

  # Test a webhook endpoint connectivity
  def test_endpoint(endpoint, test_event = nil)
    test_event ||= generate_test_event(endpoint)
    
    start_time = Time.current
    
    begin
      response = make_test_request(endpoint, test_event)
      duration = ((Time.current - start_time) * 1000).round(2) # milliseconds
      
      success = response_successful?(response)
      
      # Record the test delivery
      delivery = endpoint.webhook_deliveries.create!(
        event_type: 'test_event',
        payload: test_event.to_json,
        status: success ? 'success' : 'failed',
        response_code: response&.code&.to_i,
        response_body: truncate_response_body(response&.body),
        delivery_attempts: 1,
        delivered_at: success ? Time.current : nil
      )

      {
        success: success,
        status_code: response&.code&.to_i,
        response_time: duration,
        message: success ? 'Test webhook delivered successfully' : 'Test webhook delivery failed',
        delivery_id: delivery.id,
        response_body: response&.body&.truncate(500),
        tested_at: Time.current.iso8601
      }
      
    rescue StandardError => e
      duration = ((Time.current - start_time) * 1000).round(2)
      
      # Record the failed test delivery
      delivery = endpoint.webhook_deliveries.create!(
        event_type: 'test_event',
        payload: test_event.to_json,
        status: 'failed',
        error_message: e.message,
        delivery_attempts: 1
      )

      {
        success: false,
        status_code: nil,
        response_time: duration,
        message: "Test webhook failed: #{e.message}",
        delivery_id: delivery.id,
        error: e.message,
        tested_at: Time.current.iso8601
      }
    end
  end

  # Get webhook event statistics
  def webhook_event_stats(days: 7)
    events = @account ? WebhookEvent.joins(:account).where(account: @account) : WebhookEvent.all
    events = events.where('created_at >= ?', days.days.ago)

    total_events = events.count
    processed_events = events.processed.count
    failed_events = events.failed.count
    pending_events = events.pending.count

    provider_breakdown = events.group(:provider).count
    event_type_breakdown = events.group(:event_type).count
    daily_breakdown = events.group_by_day(:created_at, last: days).count

    success_rate = total_events > 0 ? (processed_events.to_f / total_events * 100).round(2) : 0

    {
      period: "#{days} days",
      total_events: total_events,
      processed: processed_events,
      failed: failed_events,
      pending: pending_events,
      success_rate: success_rate,
      provider_breakdown: provider_breakdown,
      event_type_breakdown: event_type_breakdown,
      daily_breakdown: daily_breakdown,
      average_events_per_day: (total_events.to_f / days).round(1)
    }
  end

  private

  def determine_overall_status(healthy, warning, unhealthy, total)
    return 'healthy' if unhealthy == 0 && warning <= (total * 0.1).ceil # Max 10% warnings
    return 'warning' if unhealthy <= (total * 0.2).ceil # Max 20% unhealthy
    'unhealthy'
  end

  def determine_endpoint_status(success_rate, total_deliveries)
    return 'insufficient_data' if total_deliveries < MIN_EVENTS_FOR_HEALTH_CHECK
    return 'healthy' if success_rate >= (HEALTHY_THRESHOLD * 100)
    return 'warning' if success_rate >= 80
    'unhealthy'
  end

  def generate_health_message(status, success_rate, total)
    case status
    when 'healthy'
      "Excellent webhook delivery rate: #{success_rate}% (#{total} deliveries)"
    when 'warning' 
      "Webhook delivery issues detected: #{success_rate}% success rate (#{total} deliveries)"
    when 'unhealthy'
      "Critical webhook delivery problems: #{success_rate}% success rate (#{total} deliveries)"
    when 'insufficient_data'
      "Not enough webhook deliveries to determine health (#{total} deliveries, need #{MIN_EVENTS_FOR_HEALTH_CHECK})"
    else
      "Unknown webhook status"
    end
  end

  def generate_test_event(endpoint)
    {
      id: "test_#{SecureRandom.hex(8)}",
      type: 'test.webhook',
      created: Time.current.to_i,
      data: {
        object: {
          id: "test_object_#{SecureRandom.hex(4)}",
          created: Time.current.to_i,
          test: true,
          message: "This is a test webhook delivery from Powernode platform"
        }
      },
      test_mode: true,
      webhook_endpoint_id: endpoint.id
    }
  end

  def make_test_request(endpoint, payload)
    uri = URI(endpoint.url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.read_timeout = HEALTH_CHECK_TIMEOUT
    http.open_timeout = HEALTH_CHECK_TIMEOUT

    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request['User-Agent'] = 'Powernode-Webhook-Health-Check/1.0'
    
    # Add any authentication headers if configured
    if endpoint.secret.present?
      signature = generate_signature(payload.to_json, endpoint.secret)
      request['X-Powernode-Signature'] = signature
    end

    request.body = payload.to_json

    http.request(request)
  end

  def response_successful?(response)
    return false unless response
    
    code = response.code.to_i
    code >= 200 && code < 300
  end

  def generate_signature(payload, secret)
    OpenSSL::HMAC.hexdigest('SHA256', secret, payload)
  end

  def truncate_response_body(body)
    return nil unless body
    body.length > 1000 ? "#{body[0..1000]}..." : body
  end
end
# frozen_string_literal: true

module ApiTestHelpers
  # API response stubs
  def stub_backend_api_success(method, path, response_data = {}, status: 200, with_query: nil)
    url = build_api_url(path)
    
    stub = WebMock.stub_request(method, url)
      .with(headers: expected_request_headers)
    
    # If specific query parameters are provided, match them exactly
    # Otherwise, allow any query parameters (or none)
    if with_query
      stub = stub.with(query: with_query)
    else
      # Use a regex pattern to match the path with any query parameters
      url_pattern = /#{Regexp.escape(url)}(\?.*)?/
      stub = WebMock.stub_request(method, url_pattern)
        .with(headers: expected_request_headers)
    end
    
    stub.to_return(
      status: status,
      body: response_data.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )
  end

  def stub_backend_api_error(method, path, status: 500, error_message: 'Server Error', with_query: nil)
    url = build_api_url(path)
    error_response = { error: error_message }
    
    stub = WebMock.stub_request(method, url)
      .with(headers: expected_request_headers)
    
    # Handle query parameters the same way as success stub
    if with_query
      stub = stub.with(query: with_query)
    else
      url_pattern = /#{Regexp.escape(url)}(\?.*)?/
      stub = WebMock.stub_request(method, url_pattern)
        .with(headers: expected_request_headers)
    end
    
    stub.to_return(
      status: status,
      body: error_response.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )
  end

  def stub_backend_api_timeout(method, path)
    url = build_api_url(path)
    url_pattern = /#{Regexp.escape(url)}(\?.*)?/
    
    WebMock.stub_request(method, url_pattern)
      .with(headers: expected_request_headers)
      .to_raise(Faraday::TimeoutError.new('execution expired'))
  end

  def stub_backend_api_connection_failure(method, path)
    url = build_api_url(path)
    url_pattern = /#{Regexp.escape(url)}(\?.*)?/
    
    WebMock.stub_request(method, url_pattern)
      .with(headers: expected_request_headers)
      .to_raise(Faraday::ConnectionFailed.new('Failed to open TCP connection'))
  end

  # Specific API endpoint stubs
  def stub_health_check_success
    stub_backend_api_success(:get, '/api/v1/health', {
      status: 'ok',
      timestamp: Time.current.iso8601
    })
  end

  def stub_service_verification_success
    stub_backend_api_success(:post, '/api/v1/service/verify', {
      success: true,
      service: 'worker',
      permissions: ['worker.execute']
    })
  end

  def stub_account_data(account_id)
    stub_backend_api_success(:get, "/api/v1/accounts/#{account_id}", {
      success: true,
      data: {
        id: account_id,
        name: 'Test Account',
        status: 'active',
        subscription: {
          plan: 'pro',
          status: 'active'
        }
      }
    })
  end

  def stub_report_generation_success(report_id = 'report-123')
    stub_backend_api_success(:post, '/api/v1/reports', {
      success: true,
      data: {
        id: report_id,
        status: 'generated',
        file_path: "/tmp/reports/#{report_id}.pdf",
        file_size: 1024
      }
    })
  end

  def stub_analytics_data(analytics_type = 'revenue')
    stub_backend_api_success(:get, "/api/v1/analytics/#{analytics_type}", {
      success: true,
      data: {
        type: analytics_type,
        metrics: [
          { date: '2024-01-01', value: 1000 },
          { date: '2024-01-02', value: 1200 }
        ]
      }
    })
  end

  def stub_job_status_update(job_id)
    stub_backend_api_success(:patch, "/api/v1/internal/jobs/#{job_id}", {
      success: true,
      data: {
        id: job_id,
        status: 'completed'
      }
    })
  end

  def stub_service_health_check
    stub_backend_api_success(:post, '/api/v1/internal/services/health_check', {
      success: true,
      data: {
        services: {
          'redis' => { status: 'healthy', response_time: 5 },
          'database' => { status: 'healthy', response_time: 12 },
          'email_service' => { status: 'healthy', response_time: 8 }
        }
      }
    })
  end

  def stub_email_delivery_success
    stub_backend_api_success(:post, '/api/v1/internal/notifications/email', {
      success: true,
      data: {
        delivery_id: 'delivery-123',
        status: 'sent',
        message_id: 'msg-456'
      }
    })
  end

  # Request verification helpers
  def expect_api_request(method, path, with_body: nil)
    url = build_api_url(path)
    
    request_expectation = a_request(method, url)
      .with(headers: expected_request_headers)
    
    if with_body
      request_expectation = request_expectation.with(body: with_body.is_a?(String) ? with_body : with_body.to_json)
    end
    
    expect(request_expectation).to have_been_made
  end

  def expect_no_api_requests
    expect(WebMock).not_to have_been_requested
  end

  # Authentication helpers
  def stub_service_authentication_success
    stub_backend_api_success(:post, '/api/v1/service/verify', {
      success: true,
      service: 'worker'
    })
  end

  def stub_service_authentication_failure
    stub_backend_api_error(:post, '/api/v1/service/verify', 
      status: 401, 
      error_message: 'Invalid service token'
    )
  end

  # WebMock helpers
  def stub_all_external_requests
    WebMock.stub_request(:any, /.*/)
      .to_return(status: 200, body: '{}', headers: {})
  end

  def disable_external_requests
    WebMock.disable_net_connect!(allow_localhost: false)
  end

  def allow_external_requests
    WebMock.allow_net_connect!
  end

  private

  def build_api_url(path)
    base_url = 'http://localhost:3000'
    "#{base_url}#{path}"
  end

  def expected_request_headers
    {
      'Authorization' => 'Bearer test-worker-token-123',
      'Content-Type' => 'application/json',
      'Accept' => 'application/json',
      'User-Agent' => 'PowernodeWorker/1.0'
    }
  end
end
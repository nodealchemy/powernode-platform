# frozen_string_literal: true

module WorkerTestHelpers
  # Test configuration helpers
  def test_config
    @test_config ||= {
      backend_api_url: 'http://test-backend.local',
      worker_token: 'test-worker-token-123',
      service_token: 'test-service-token-456',
      api_timeout: 10,
      max_retry_attempts: 2
    }
  end

  def mock_powernode_worker_config
    config_double = double('Configuration')
    allow(config_double).to receive(:backend_api_url).and_return(test_config[:backend_api_url])
    allow(config_double).to receive(:worker_token).and_return(test_config[:worker_token])
    allow(config_double).to receive(:api_timeout).and_return(test_config[:api_timeout])
    allow(config_double).to receive(:max_retry_attempts).and_return(test_config[:max_retry_attempts])
    
    app_double = double('Application')
    allow(app_double).to receive(:config).and_return(config_double)
    allow(app_double).to receive(:logger).and_return(Logger.new('/dev/null'))
    
    allow(PowernodeWorker).to receive(:application).and_return(app_double)
    
    config_double
  end

  # Time helpers for testing
  def freeze_time_at(time)
    allow(Time).to receive(:current).and_return(time)
    allow(Time).to receive(:now).and_return(time)
    time
  end

  def travel_to(time, &block)
    original_time = Time.current
    freeze_time_at(time)
    yield
  ensure
    allow(Time).to receive(:current).and_call_original
    allow(Time).to receive(:now).and_call_original
  end

  # Job execution helpers
  def perform_job(job_class, *args)
    job_class.new.perform(*args)
  end

  def perform_job_with_execute(job_class, *args)
    job_class.new.execute(*args)
  end

  # Sidekiq testing helpers
  def expect_job_enqueued(job_class, with_args: nil, count: 1)
    if with_args
      expect(job_class).to have_enqueued_sidekiq_job(*with_args)
    else
      expect(job_class.jobs.size).to eq(count)
    end
  end

  def expect_no_jobs_enqueued(job_class = nil)
    if job_class
      expect(job_class.jobs).to be_empty
    else
      expect(Sidekiq::Worker.jobs).to be_empty
    end
  end

  def clear_all_jobs
    Sidekiq::Worker.clear_all
  end

  # Error simulation helpers
  def simulate_api_error(status: 500, message: 'Server Error', response_body: {})
    BackendApiClient::ApiError.new(message, status, response_body)
  end

  def simulate_network_timeout
    Faraday::TimeoutError.new('Request timeout')
  end

  def simulate_connection_failure
    Faraday::ConnectionFailed.new('Connection failed')
  end

  # Test data factories
  def sample_email_data
    {
      'to' => 'test@example.com',
      'subject' => 'Test Email',
      'body' => 'Test email body content',
      'email_type' => 'notification',
      'from' => 'noreply@powernode.com',
      'template' => 'notification',
      'template_data' => { 'name' => 'Test User' }
    }
  end

  def sample_report_data
    {
      'report_type' => 'analytics',
      'account_id' => 'account-123',
      'parameters' => {
        'start_date' => '2024-01-01',
        'end_date' => '2024-01-31',
        'metrics' => ['revenue', 'users']
      }
    }
  end

  def sample_webhook_data
    {
      'id' => 'webhook-123',
      'type' => 'stripe',
      'event_type' => 'payment.succeeded',
      'data' => {
        'payment_id' => 'pay_123',
        'amount' => 2500,
        'currency' => 'usd'
      }
    }
  end

  def sample_service_config
    {
      'service_name' => 'test-service',
      'config_data' => {
        'host' => 'test.example.com',
        'port' => 8080,
        'ssl' => true
      },
      'environment' => 'test'
    }
  end

  # Validation helpers
  def expect_valid_job_result(result, expected_status: 'completed')
    expect(result).to be_a(Hash)
    expect(result).to have_key('status')
    expect(result['status']).to eq(expected_status)
  end

  def expect_api_client_called_with(method, path, data = nil)
    if data
      expect_any_instance_of(BackendApiClient).to have_received(method).with(path, data)
    else
      expect_any_instance_of(BackendApiClient).to have_received(method).with(path)
    end
  end

  # Logging helpers
  def expect_log_message(level, message_pattern)
    expect(PowernodeWorker.application.logger).to have_received(level) do |&block|
      expect(block.call).to match(message_pattern)
    end
  end

  def mock_logger
    logger_double = double('Logger')
    allow(logger_double).to receive(:info)
    allow(logger_double).to receive(:warn)
    allow(logger_double).to receive(:error)
    allow(logger_double).to receive(:debug)
    allow(PowernodeWorker.application).to receive(:logger).and_return(logger_double)
    logger_double
  end
end
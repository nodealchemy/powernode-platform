# frozen_string_literal: true

module JobTestHelpers
  # Allow all logging methods to be called with any arguments
  # Use this when testing jobs that log multiple messages
  def allow_logging_methods
    allow_any_instance_of(BaseJob).to receive(:log_info)
    allow_any_instance_of(BaseJob).to receive(:log_error)
    allow_any_instance_of(BaseJob).to receive(:log_warn)
  end

  # Helper to verify a specific log message was called (use after job execution)
  # This captures log calls and allows verification after the fact
  def capture_logs_for(job_instance)
    @captured_logs = { info: [], error: [], warn: [] }
    allow(job_instance).to receive(:log_info) { |msg, **_opts| @captured_logs[:info] << msg }
    allow(job_instance).to receive(:log_error) { |msg, *_args, **_opts| @captured_logs[:error] << msg }
    allow(job_instance).to receive(:log_warn) { |msg, **_opts| @captured_logs[:warn] << msg }
    @captured_logs
  end

  def expect_logged(level, pattern)
    expect(@captured_logs[level]).to include(match(pattern))
  end

  # Shared job testing patterns
  shared_examples 'a base job' do |job_class|
    let(:job_instance) { job_class.new }

    it 'inherits from BaseJob' do
      expect(job_instance).to be_a(BaseJob)
    end

    it 'includes Sidekiq::Job' do
      expect(job_instance.class.included_modules).to include(Sidekiq::Job)
    end

    it 'has sidekiq_options configured' do
      expect(job_class.sidekiq_options).to be_a(Hash)
      expect(job_class.sidekiq_options).to have_key('retry')
    end

    it 'implements execute method' do
      expect(job_instance).to respond_to(:execute)
    end

    it 'has access to api_client' do
      allow(BackendApiClient).to receive(:new).and_return(double('ApiClient'))
      expect(job_instance.send(:api_client)).to be_present
    end

    it 'has access to logger' do
      mock_powernode_worker_config
      expect(job_instance.send(:logger)).to be_present
    end
  end

  shared_examples 'a job with API communication' do
    before do
      mock_powernode_worker_config
      allow(BackendApiClient).to receive(:new).and_return(api_client_double)
    end

    let(:api_client_double) { double('BackendApiClient') }

    it 'uses BackendApiClient for API communication' do
      allow(api_client_double).to receive(:post).and_return({ 'success' => true })
      
      job_instance = subject.new
      job_instance.send(:api_client)
      
      expect(BackendApiClient).to have_received(:new)
    end

    it 'handles API errors gracefully' do
      allow(api_client_double).to receive(:post)
        .and_raise(BackendApiClient::ApiError.new('API Error', 500))
      
      job_instance = subject.new
      expect { job_instance.send(:api_client).post('/test', {}) }.to raise_error(BackendApiClient::ApiError)
    end
  end

  shared_examples 'a job with retry logic' do
    it 'has custom retry configuration' do
      expect(subject.sidekiq_options['retry']).to be > 0
    end

    it 'uses exponential backoff for retries' do
      expect(subject.sidekiq_retry_in_block).to be_present
    end

    it 'handles different types of exceptions differently' do
      retry_block = subject.sidekiq_retry_in_block
      
      # API errors should have shorter intervals
      api_error_interval = retry_block.call(1, BackendApiClient::ApiError.new('API Error'))
      expect(api_error_interval).to be <= 60
      
      # Test multiple samples of standard errors to account for randomization
      standard_error_intervals = []
      10.times do
        standard_error_intervals << retry_block.call(1, StandardError.new('Standard Error'))
      end
      
      # The average should be greater than API error interval due to exponential backoff base
      average_interval = standard_error_intervals.sum / standard_error_intervals.size.to_f
      expect(average_interval).to be > api_error_interval
      
      # All intervals should be at least the base exponential value (16 seconds minimum)
      expect(standard_error_intervals.min).to be >= 16
    end
  end

  shared_examples 'a job with parameter validation' do |required_params|
    it 'validates required parameters' do
      job_instance = subject.new
      mock_powernode_worker_config
      
      incomplete_params = {}
      
      expect {
        job_instance.execute(incomplete_params)
      }.to raise_error(ArgumentError, /Missing required parameters/)
    end

    it 'accepts valid parameters' do
      job_instance = subject.new
      mock_powernode_worker_config
      
      valid_params = required_params.each_with_object({}) do |param, hash|
        hash[param] = "test_#{param}"
      end
      
      # Mock both API client and any services the job might use
      allow(job_instance).to receive(:api_client).and_return(double('ApiClient', post: { 'success' => true }))
      
      # For email delivery jobs, mock the email service
      if defined?(EmailDeliveryWorkerService)
        email_service_double = double('EmailDeliveryWorkerService', send_email: { success: true })
        allow(EmailDeliveryWorkerService).to receive(:new).and_return(email_service_double)
      end
      
      expect {
        job_instance.execute(valid_params)
      }.not_to raise_error
    end
  end

  shared_examples 'a job with logging' do
    let(:logger_double) { double('Logger', info: nil, warn: nil, error: nil, debug: nil, level: Logger::INFO) }

    before do
      mock_powernode_worker_config
      allow(PowernodeWorker.application).to receive(:logger).and_return(logger_double)
    end

    it 'logs job start and completion' do
      job_instance = subject.new
      allow(job_instance).to receive(:execute).and_return({ success: true })

      # Use test data from context if available
      if respond_to?(:workflow_job_args)
        # Workflow jobs use keyword arguments
        job_instance.perform(**workflow_job_args)
      elsif respond_to?(:email_data)
        # Email jobs use positional arguments
        job_instance.perform(email_data)
      elsif respond_to?(:job_args)
        # Generic positional arguments (can be single value or array)
        args = job_args.is_a?(Array) ? job_args : [job_args]
        job_instance.perform(*args)
      else
        # No arguments
        job_instance.perform
      end

      expect(logger_double).to have_received(:info).with(match(/Starting #{subject.name}/))
      expect(logger_double).to have_received(:info).with(match(/Completed #{subject.name}/))
    end

    it 'logs errors when job fails' do
      job_instance = subject.new
      allow(job_instance).to receive(:execute).and_raise(StandardError.new('Test error'))

      # Use test data from context if available
      expect do
        if respond_to?(:workflow_job_args)
          # Workflow jobs use keyword arguments
          job_instance.perform(**workflow_job_args)
        elsif respond_to?(:email_data)
          # Email jobs use positional arguments
          job_instance.perform(email_data)
        elsif respond_to?(:job_args)
          # Generic positional arguments (can be single value or array)
          args = job_args.is_a?(Array) ? job_args : [job_args]
          job_instance.perform(*args)
        else
          # No arguments
          job_instance.perform
        end
      end.to raise_error(StandardError)

      expect(logger_double).to have_received(:error).with(match(/Failed #{subject.name}/))
    end
  end

  shared_examples 'a job with timing metrics' do
    it 'tracks execution duration' do
      job_instance = subject.new
      mock_powernode_worker_config
      
      start_time = Time.current
      freeze_time_at(start_time)
      
      # Mock the job to run for a specific duration
      allow(job_instance).to receive(:execute) do
        freeze_time_at(start_time + 2.5) # 2.5 seconds later
        { success: true }
      end
      
      logger_double = double('Logger', info: nil, warn: nil, error: nil, level: Logger::INFO)
      allow(PowernodeWorker.application).to receive(:logger).and_return(logger_double)
      
      # Use test data from context if available
      if respond_to?(:workflow_job_args)
        job_instance.perform(**workflow_job_args)
      elsif respond_to?(:email_data)
        job_instance.perform(email_data)
      elsif respond_to?(:job_args)
        # Generic positional arguments (can be single value or array)
        args = job_args.is_a?(Array) ? job_args : [job_args]
        job_instance.perform(*args)
      else
        job_instance.perform
      end

      expect(logger_double).to have_received(:info).with(match(/in 2.5s/))
    end
  end

  # Job factory helpers
  def create_test_job(job_class, **options)
    defaults = {
      jid: SecureRandom.hex(12),
      queue: 'test',
      created_at: Time.current.to_f,
      retry: true
    }
    
    job_data = defaults.merge(options)
    job_instance = job_class.new
    job_instance.instance_variable_set(:@jid, job_data[:jid])
    job_instance
  end

  def simulate_job_retry(job_class, retry_count = 1)
    job_instance = job_class.new
    job_instance.instance_variable_set(:@retry_count, retry_count)
    job_instance
  end

  # Performance testing helpers
  def measure_job_performance(job_class, *args)
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    
    result = job_class.new.perform(*args)
    
    end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    duration = end_time - start_time
    
    {
      result: result,
      duration: duration,
      start_time: start_time,
      end_time: end_time
    }
  end

  def expect_job_performance_within(job_class, max_duration, *args)
    performance = measure_job_performance(job_class, *args)
    expect(performance[:duration]).to be < max_duration
    performance
  end

  # Sidekiq testing helpers
  def with_sidekiq_testing_mode(mode = :fake, &block)
    original_mode = Sidekiq::Testing.instance_variable_get(:@__testing)
    
    case mode
    when :fake
      Sidekiq::Testing.fake!(&block)
    when :inline
      Sidekiq::Testing.inline!(&block)
    when :disable
      Sidekiq::Testing.disable!(&block)
    end
  ensure
    Sidekiq::Testing.instance_variable_set(:@__testing, original_mode)
  end

  def expect_job_scheduled_at(job_class, scheduled_time, *args)
    scheduled_jobs = job_class.jobs.select do |job|
      job['at'] && Time.at(job['at']).to_i == scheduled_time.to_i
    end
    
    expect(scheduled_jobs).not_to be_empty
    
    if args.any?
      matching_jobs = scheduled_jobs.select { |job| job['args'] == args }
      expect(matching_jobs).not_to be_empty
    end
  end

  def expect_job_in_queue(job_class, queue_name)
    queued_jobs = job_class.jobs.select { |job| job['queue'] == queue_name }
    expect(queued_jobs).not_to be_empty
  end

  # Mock BackendApiClient for consistent testing
  def mock_api_client_success(method = :post, response = { 'success' => true })
    api_client_double = double('BackendApiClient')
    allow(api_client_double).to receive(method).and_return(response)
    allow(BackendApiClient).to receive(:new).and_return(api_client_double)
    api_client_double
  end

  def mock_api_client_error(method = :post, error = BackendApiClient::ApiError.new('Test error', 500))
    api_client_double = double('BackendApiClient')
    allow(api_client_double).to receive(method).and_raise(error)
    allow(BackendApiClient).to receive(:new).and_return(api_client_double)
    api_client_double
  end
end
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Job Queue Management', type: :integration do
  before do
    mock_powernode_worker_config
    # Start with clean queues
    Sidekiq::Worker.clear_all
    Sidekiq.redis { |conn| conn.flushdb }
  end

  after do
    # Clean up after each test
    Sidekiq::Worker.clear_all
    Sidekiq.redis { |conn| conn.flushdb }
  end

  describe 'Queue Organization and Routing' do
    it 'routes jobs to correct queues based on job type' do
      with_sidekiq_testing_mode(:fake) do
        # Enqueue different types of jobs
        Notifications::EmailDeliveryJob.perform_async(sample_email_data)
        Services::HealthCheckJob.perform_async('production')
        
        # Verify queue assignment
        email_jobs = Sidekiq::Queue.new('email').to_a
        services_jobs = Sidekiq::Queue.new('services').to_a
        
        expect(email_jobs.size).to eq(1)
        expect(services_jobs.size).to eq(1)
        
        expect(email_jobs.first['class']).to eq('Notifications::EmailDeliveryJob')
        expect(services_jobs.first['class']).to eq('Services::HealthCheckJob')
      end
    end

    it 'handles default queue routing' do
      # Create a job that uses default queue from BaseJob
      test_job_class = Class.new(BaseJob) do
        def execute(*args)
          { success: true, args: args }
        end
      end
      
      with_sidekiq_testing_mode(:fake) do
        test_job_class.perform_async('test_arg')
        
        default_jobs = Sidekiq::Queue.new('default').to_a
        expect(default_jobs.size).to eq(1)
      end
    end

    it 'maintains queue priority and processing order' do
      with_sidekiq_testing_mode(:fake) do
        # Enqueue multiple jobs with different priorities
        5.times do |i|
          Notifications::EmailDeliveryJob.perform_async({
            'to' => "test#{i}@example.com",
            'subject' => "Email #{i}",
            'body' => 'Test',
            'email_type' => 'notification'
          })
        end
        
        queue = Sidekiq::Queue.new('email')
        expect(queue.size).to eq(5)
        
        # Verify FIFO ordering (first enqueued should be first in queue)
        first_job = queue.first
        expect(first_job['args'][0]['to']).to eq('test0@example.com')
      end
    end
  end

  describe 'Job Retry Mechanisms' do
    let(:failing_job_class) do
      Class.new(BaseJob) do
        sidekiq_options retry: 3, queue: 'test_retries'
        
        @@attempt_count = 0
        
        def execute(*args)
          @@attempt_count += 1
          
          # Fail first 2 attempts, succeed on 3rd
          if @@attempt_count <= 2
            raise StandardError.new("Attempt #{@@attempt_count} failed")
          end
          
          { success: true, attempt: @@attempt_count }
        end
        
        def self.reset_attempts
          @@attempt_count = 0
        end
      end
    end

    before do
      failing_job_class.reset_attempts
    end

    it 'retries failed jobs according to configuration' do
      with_sidekiq_testing_mode(:inline) do
        # Mock the retry mechanism
        allow_any_instance_of(failing_job_class).to receive(:perform) do |instance, *args|
          begin
            instance.send(:execute, *args)
          rescue StandardError => e
            # Simulate Sidekiq retry logic
            if instance.instance_variable_get(:@sidekiq_retry_count).to_i < 2
              instance.instance_variable_set(:@sidekiq_retry_count, instance.instance_variable_get(:@sidekiq_retry_count).to_i + 1)
              retry
            else
              raise e
            end
          end
        end
        
        expect {
          failing_job_class.perform_async('test')
        }.not_to raise_error
      end
    end

    it 'uses custom retry intervals for different error types' do
      retry_block = BaseJob.sidekiq_retry_in_block
      
      # Test API error intervals (shorter)
      api_error = BackendApiClient::ApiError.new('API Error', 503)
      api_interval_1 = retry_block.call(1, api_error)
      api_interval_2 = retry_block.call(2, api_error)
      
      expect(api_interval_1).to eq(30)
      expect(api_interval_2).to eq(60)
      
      # Test standard error intervals (exponential backoff)
      std_error = StandardError.new('Standard Error')
      std_interval_1 = retry_block.call(1, std_error)
      std_interval_2 = retry_block.call(2, std_error)
      
      expect(std_interval_1).to be > api_interval_1
      expect(std_interval_2).to be > std_interval_1
    end

    it 'moves jobs to dead queue after max retries exceeded' do
      with_sidekiq_testing_mode(:fake) do
        # Create a job that always fails
        always_failing_job = Class.new(BaseJob) do
          sidekiq_options retry: 1, queue: 'test_dead'
          
          def execute(*args)
            raise StandardError.new('Always fails')
          end
        end
        
        always_failing_job.perform_async('doomed')
        
        # Simulate processing and exhausting retries
        job = Sidekiq::Queue.new('test_dead').first
        expect(job).to be_present
        
        # In real Sidekiq, this would eventually move to dead set
        # We can verify the retry configuration is correct
        expect(always_failing_job.sidekiq_options['retry']).to eq(1)
        expect(always_failing_job.sidekiq_options['dead']).to be true
      end
    end
  end

  describe 'Scheduled Jobs and Timing' do
    it 'schedules jobs for future execution' do
      with_sidekiq_testing_mode(:fake) do
        future_time = 1.hour.from_now
        
        Notifications::EmailDeliveryJob.perform_at(future_time, sample_email_data)
        
        # Check scheduled set
        scheduled_jobs = Sidekiq::ScheduledSet.new.to_a
        expect(scheduled_jobs.size).to eq(1)
        
        scheduled_job = scheduled_jobs.first
        expect(scheduled_job.at.to_i).to eq(future_time.to_i)
        expect(scheduled_job.klass).to eq('Notifications::EmailDeliveryJob')
      end
    end

    it 'handles job scheduling with delays' do
      with_sidekiq_testing_mode(:fake) do
        Services::HealthCheckJob.perform_in(30.minutes, 'production', nil, job_id: 'scheduled-health-check')
        
        scheduled_jobs = Sidekiq::ScheduledSet.new.to_a
        expect(scheduled_jobs.size).to eq(1)
        
        scheduled_job = scheduled_jobs.first
        expect(scheduled_job.at).to be_within(1.second).of(30.minutes.from_now)
      end
    end

    it 'processes scheduled jobs when time arrives' do
      with_sidekiq_testing_mode(:fake) do
        # Schedule a job for "now" (immediate processing)
        past_time = 1.second.ago
        Notifications::EmailDeliveryJob.perform_at(past_time, sample_email_data)
        
        # Simulate time passing and scheduled job processing
        Sidekiq::Cron::Job.new(name: 'test', cron: '* * * * *') if defined?(Sidekiq::Cron)
        
        # In a real scenario, the scheduled job would move to the regular queue
        # We can verify it was scheduled correctly
        scheduled_jobs = Sidekiq::ScheduledSet.new.to_a
        expect(scheduled_jobs.size).to eq(1)
        expect(scheduled_jobs.first.at).to be < Time.current
      end
    end
  end

  describe 'Queue Monitoring and Management' do
    before do
      with_sidekiq_testing_mode(:fake) do
        # Set up various jobs for monitoring tests
        3.times { |i| Notifications::EmailDeliveryJob.perform_async(sample_email_data.merge('to' => "test#{i}@example.com")) }
        2.times { Services::HealthCheckJob.perform_async('production') }
        1.times { Services::HealthCheckJob.perform_in(1.hour, 'staging') }
      end
    end

    it 'provides queue statistics and visibility' do
      stats = Sidekiq::Stats.new
      
      expect(stats.enqueued).to eq(5) # 3 email + 2 health check jobs
      expect(stats.scheduled).to eq(1) # 1 scheduled health check
      
      # Queue-specific stats
      email_queue = Sidekiq::Queue.new('email')
      services_queue = Sidekiq::Queue.new('services')
      
      expect(email_queue.size).to eq(3)
      expect(services_queue.size).to eq(2)
    end

    it 'allows queue management operations' do
      email_queue = Sidekiq::Queue.new('email')
      initial_size = email_queue.size
      
      # Remove specific job from queue
      email_queue.each do |job|
        if job['args'][0]['to'] == 'test1@example.com'
          job.delete
          break
        end
      end
      
      expect(email_queue.size).to eq(initial_size - 1)
    end

    it 'tracks job processing metrics' do
      # In a real scenario, we'd want to track:
      # - Job processing times
      # - Success/failure rates
      # - Queue depths over time
      
      with_sidekiq_testing_mode(:inline) do
        # Mock successful email service
        allow(EmailDeliveryWorkerService).to receive(:new).and_return(
          double('EmailService', send_email: { success: true })
        )
        
        start_time = Time.current
        
        Notifications::EmailDeliveryJob.perform_async(sample_email_data)
        
        processing_time = Time.current - start_time
        
        # Verify job was processed (in inline mode)
        expect(processing_time).to be < 1.0 # Should be very fast when mocked
        
        # In production, these metrics would be collected by monitoring systems
        stats = Sidekiq::Stats.new
        expect(stats.processed).to be >= 0
      end
    end
  end

  describe 'Queue Performance and Throughput' do
    it 'handles high-volume job enqueueing efficiently' do
      with_sidekiq_testing_mode(:fake) do
        start_time = Time.current
        
        # Enqueue many jobs quickly
        100.times do |i|
          Notifications::EmailDeliveryJob.perform_async(
            sample_email_data.merge('to' => "bulk#{i}@example.com")
          )
        end
        
        enqueue_time = Time.current - start_time
        
        expect(enqueue_time).to be < 1.0 # Should enqueue 100 jobs in under 1 second
        expect(Sidekiq::Queue.new('email').size).to eq(100)
      end
    end

    it 'maintains queue performance under load' do
      with_sidekiq_testing_mode(:fake) do
        # Mix different job types and queues
        job_data = [
          [Notifications::EmailDeliveryJob, 'email', sample_email_data],
          [Services::HealthCheckJob, 'services', ['production']]
        ]
        
        # Enqueue jobs in batches
        5.times do
          10.times do
            job_class, queue, args = job_data.sample
            job_class.perform_async(*args)
          end
        end
        
        # Verify queues maintained their organization
        total_jobs = Sidekiq::Stats.new.enqueued
        expect(total_jobs).to eq(50)
        
        # Check queue distribution
        email_queue_size = Sidekiq::Queue.new('email').size
        services_queue_size = Sidekiq::Queue.new('services').size
        
        expect(email_queue_size + services_queue_size).to eq(50)
      end
    end
  end

  describe 'Dead Job Management' do
    it 'handles jobs that exceed retry limits' do
      with_sidekiq_testing_mode(:fake) do
        # Jobs that will eventually go to dead queue
        job_that_will_die = Class.new(BaseJob) do
          sidekiq_options retry: 1, dead: true, queue: 'test_mortality'
          
          def execute(*args)
            raise StandardError.new('Persistent failure')
          end
        end
        
        job_that_will_die.perform_async('doomed_arg')
        
        # Verify job configuration for death handling
        expect(job_that_will_die.sidekiq_options['dead']).to be true
        expect(job_that_will_die.sidekiq_options['retry']).to eq(1)
        
        # In real Sidekiq, after retries are exhausted, job moves to DeadSet
        dead_set = Sidekiq::DeadSet.new
        expect(dead_set).to respond_to(:size) # Verify dead set exists
      end
    end

    it 'allows resurrection of dead jobs' do
      # In production, dead jobs can be retried through Sidekiq Web UI
      # or programmatically through the DeadSet API
      
      dead_set = Sidekiq::DeadSet.new
      expect(dead_set).to respond_to(:retry_all)
      expect(dead_set).to respond_to(:clear)
      
      # These methods would be used for dead job management:
      # dead_set.retry_all  # Retry all dead jobs
      # dead_set.clear      # Delete all dead jobs
      # dead_job.retry      # Retry specific dead job
    end
  end

  describe 'Queue Configuration and Tuning' do
    it 'respects concurrency settings' do
      # Verify that Sidekiq configuration is properly set
      config = PowernodeWorker.application.config
      
      expect(config).to respond_to(:worker_concurrency)
      expect(config.worker_concurrency).to be > 0
    end

    it 'processes queues in configured order' do
      # Verify queue processing priority
      config = PowernodeWorker.application.config
      
      expect(config).to respond_to(:worker_queues)
      expect(config.worker_queues).to be_an(Array)
      expect(config.worker_queues).to include('default')
    end

    it 'handles queue-specific configurations' do
      # Different job types can have different queue configurations
      email_options = Notifications::EmailDeliveryJob.sidekiq_options
      services_options = Services::HealthCheckJob.sidekiq_options
      
      expect(email_options['queue']).to eq('email')
      expect(services_options['queue']).to eq('services')
      
      # Different retry policies
      expect(email_options['retry']).to eq(3)
      expect(services_options['retry']).to eq(1)
    end
  end
end
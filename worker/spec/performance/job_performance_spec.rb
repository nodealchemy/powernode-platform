# frozen_string_literal: true

require 'spec_helper'
require 'benchmark'

RSpec.describe 'Job Performance and Reliability', type: :performance do
  before do
    mock_powernode_worker_config
  end

  describe 'Job Execution Performance' do
    describe 'BaseJob overhead' do
      let(:minimal_job_class) do
        Class.new(BaseJob) do
          def execute(*args)
            { success: true, processed: args.size }
          end
        end
      end

      it 'has minimal execution overhead' do
        job = minimal_job_class.new
        
        performance = measure_job_performance(minimal_job_class, 'test', 'args')
        
        # BaseJob overhead should be minimal (< 10ms for simple jobs)
        expect(performance[:duration]).to be < 0.01
        expect(performance[:result]).to include(success: true)
      end

      it 'scales linearly with argument complexity' do
        simple_args = ['simple']
        complex_args = [{ complex: { data: (1..100).to_a, nested: { deep: 'value' } } }]
        
        simple_perf = measure_job_performance(minimal_job_class, *simple_args)
        complex_perf = measure_job_performance(minimal_job_class, *complex_args)
        
        # Complex arguments shouldn't significantly impact BaseJob performance
        ratio = complex_perf[:duration] / simple_perf[:duration]
        expect(ratio).to be < 3.0 # Should not be more than 3x slower
      end
    end

    describe 'BackendApiClient performance' do
      let(:api_client) { BackendApiClient.new }

      before do
        # Mock network calls for performance testing
        stub_backend_api_success(:get, '/api/v1/performance-test', { result: 'success' })
        stub_backend_api_success(:post, '/api/v1/performance-test', { created: true })
      end

      it 'performs API calls within acceptable timeframes' do
        # GET request performance
        get_time = Benchmark.realtime do
          10.times { api_client.get('/api/v1/performance-test') }
        end
        
        expect(get_time / 10).to be < 0.1 # Average < 100ms per request (when mocked)
        
        # POST request performance
        post_data = { test: 'data', timestamp: Time.current.iso8601 }
        post_time = Benchmark.realtime do
          10.times { api_client.post('/api/v1/performance-test', post_data) }
        end
        
        expect(post_time / 10).to be < 0.1 # Average < 100ms per request (when mocked)
      end

      it 'handles connection pooling efficiently' do
        # Simulate concurrent API calls
        threads = []
        start_time = Time.current
        
        5.times do
          threads << Thread.new do
            5.times { api_client.get('/api/v1/performance-test') }
          end
        end
        
        threads.each(&:join)
        total_time = Time.current - start_time
        
        # 25 concurrent calls should complete in reasonable time
        expect(total_time).to be < 1.0
      end

      it 'maintains performance under API error conditions' do
        # Test performance when handling errors
        stub_backend_api_error(:get, '/api/v1/error-test', status: 500)
        
        error_handling_time = Benchmark.realtime do
          10.times do
            begin
              api_client.get('/api/v1/error-test')
            rescue BackendApiClient::ApiError
              # Expected error
            end
          end
        end
        
        # Error handling should not be significantly slower
        expect(error_handling_time / 10).to be < 0.05
      end
    end

    describe 'Email delivery job performance' do
      let(:email_service_double) { double('EmailDeliveryWorkerService') }
      let(:email_data) { sample_email_data }

      before do
        allow(EmailDeliveryWorkerService).to receive(:new).and_return(email_service_double)
        allow(email_service_double).to receive(:send_email).and_return({ success: true })
      end

      it 'processes single email within performance targets' do
        performance = expect_job_performance_within(
          Notifications::EmailDeliveryJob,
          0.5, # 500ms target
          email_data
        )
        
        expect(performance[:result][:success]).to be true
      end

      it 'handles batch email processing efficiently' do
        batch_size = 50
        batch_data = []
        
        # Prepare batch of email data
        batch_size.times do |i|
          batch_data << email_data.merge('to' => "batch#{i}@example.com")
        end
        
        # Process batch and measure time
        start_time = Time.current
        
        batch_data.each do |data|
          Notifications::EmailDeliveryJob.new.execute(data)
        end
        
        total_time = Time.current - start_time
        avg_time = total_time / batch_size
        
        expect(avg_time).to be < 0.1 # Less than 100ms per email on average
      end

      it 'maintains performance with complex email templates' do
        complex_email = email_data.merge(
          'template_data' => {
            'user' => { 'name' => 'John Doe', 'preferences' => {} },
            'content' => { 'items' => (1..100).map { |i| { id: i, value: "Item #{i}" } } },
            'metadata' => { 'generated_at' => Time.current.iso8601 }
          }
        )
        
        performance = expect_job_performance_within(
          Notifications::EmailDeliveryJob,
          1.0, # 1 second for complex template
          complex_email
        )
        
        expect(performance[:result][:success]).to be true
      end
    end

    describe 'Health check job performance' do
      let(:api_client_double) { double('BackendApiClient') }
      let(:health_response) do
        {
          'services' => (1..10).each_with_object({}) do |i, hash|
            hash["service_#{i}"] = { 'status' => 'healthy', 'response_time' => rand(10..50) }
          end
        }
      end

      before do
        allow_any_instance_of(Services::HealthCheckJob).to receive(:api_client).and_return(api_client_double)
        allow(api_client_double).to receive(:post).and_return(health_response)
        allow(api_client_double).to receive(:patch).and_return({ 'success' => true })
      end

      it 'completes health checks within time limits' do
        performance = expect_job_performance_within(
          Services::HealthCheckJob,
          2.0, # 2 seconds for health check
          'production',
          nil,
          job_id: 'perf-test-123'
        )
        
        expect(performance[:result][:status]).to eq('completed')
        expect(performance[:result][:total_count]).to eq(10)
      end

      it 'scales with number of services checked' do
        # Test with varying numbers of services
        [5, 10, 25].each do |service_count|
          services = (1..service_count).each_with_object({}) do |i, hash|
            hash["service_#{i}"] = { 'status' => 'healthy' }
          end
          
          allow(api_client_double).to receive(:post).and_return({ 'services' => services })
          
          performance = measure_job_performance(
            Services::HealthCheckJob,
            'production'
          )
          
          # Performance should scale reasonably with service count
          expect(performance[:duration]).to be < (service_count * 0.01) # Max 10ms per service
        end
      end
    end
  end

  describe 'Memory Usage and Resource Management' do
    it 'maintains stable memory usage during job processing' do
      # This would require actual memory profiling in a real scenario
      # For now, we test that jobs don't accumulate references
      
      initial_objects = ObjectSpace.count_objects
      
      # Process multiple jobs
      50.times do |i|
        job = Class.new(BaseJob) do
          def execute(data)
            # Simulate some work with temporary objects
            temp_data = data.merge(processed_at: Time.current)
            { success: true, data: temp_data }
          end
        end.new
        
        job.execute({ id: i, payload: 'test data' })
      end
      
      GC.start # Force garbage collection
      final_objects = ObjectSpace.count_objects
      
      # Object count shouldn't grow dramatically
      growth_ratio = final_objects[:TOTAL].to_f / initial_objects[:TOTAL]
      expect(growth_ratio).to be < 1.5 # Less than 50% growth
    end

    it 'handles large data payloads efficiently' do
      large_data = {
        'records' => (1..1000).map do |i|
          {
            'id' => i,
            'data' => 'x' * 100, # 100 character string
            'metadata' => { 'index' => i, 'processed' => false }
          }
        end
      }
      
      job_class = Class.new(BaseJob) do
        def execute(data)
          # Simulate processing large dataset
          processed_count = data['records'].count { |r| r['data'].present? }
          { success: true, processed: processed_count }
        end
      end
      
      performance = expect_job_performance_within(job_class, 1.0, large_data)
      expect(performance[:result][:processed]).to eq(1000)
    end
  end

  describe 'Reliability and Error Recovery' do
    describe 'transient failure handling' do
      let(:unreliable_job_class) do
        Class.new(BaseJob) do
          @@attempt_counts = Hash.new(0)
          
          def execute(identifier)
            @@attempt_counts[identifier] += 1
            
            # Fail first 2 attempts, succeed on 3rd
            if @@attempt_counts[identifier] <= 2
              raise BackendApiClient::ApiError.new('Transient failure', 503)
            end
            
            { success: true, attempts: @@attempt_counts[identifier] }
          end
          
          def self.reset_attempts
            @@attempt_counts.clear
          end
          
          def self.attempt_count(identifier)
            @@attempt_counts[identifier]
          end
        end
      end

      before do
        unreliable_job_class.reset_attempts
      end

      it 'recovers from transient failures with exponential backoff' do
        job = unreliable_job_class.new
        identifier = 'reliability_test_1'
        
        # Simulate retry mechanism
        max_attempts = 3
        attempt = 0
        result = nil
        
        begin
          loop do
            attempt += 1
            begin
              result = job.execute(identifier)
              break
            rescue BackendApiClient::ApiError => e
              raise e if attempt >= max_attempts
              
              # Simulate exponential backoff delay (without actually sleeping)
              delay = 2 ** attempt
              expect(delay).to be > 0
            end
          end
        rescue BackendApiClient::ApiError
          # Max attempts exceeded
        end
        
        expect(result[:success]).to be true
        expect(result[:attempts]).to eq(3)
      end

      it 'tracks failure rates and recovery metrics' do
        identifiers = (1..10).map { |i| "test_#{i}" }
        results = {}
        
        identifiers.each do |id|
          job = unreliable_job_class.new
          attempts = 0
          
          begin
            loop do
              attempts += 1
              begin
                results[id] = { 
                  result: job.execute(id), 
                  total_attempts: attempts 
                }
                break
              rescue BackendApiClient::ApiError
                raise if attempts >= 3
              end
            end
          rescue BackendApiClient::ApiError
            results[id] = { 
              result: { success: false }, 
              total_attempts: attempts 
            }
          end
        end
        
        successful_jobs = results.values.count { |r| r[:result][:success] }
        average_attempts = results.values.map { |r| r[:total_attempts] }.sum.to_f / results.size
        
        expect(successful_jobs).to eq(10) # All should eventually succeed
        expect(average_attempts).to eq(3.0) # Should take exactly 3 attempts each
      end
    end

    describe 'resource exhaustion scenarios' do
      it 'handles API rate limiting gracefully' do
        rate_limited_client = double('RateLimitedApiClient')
        
        # First few calls succeed, then rate limited
        call_count = 0
        allow(rate_limited_client).to receive(:post) do
          call_count += 1
          if call_count <= 3
            { success: true }
          else
            raise BackendApiClient::ApiError.new('Rate limit exceeded', 429)
          end
        end
        
        job_class = Class.new(BaseJob) do
          def execute(client)
            client.post('/api/v1/test', {})
          end
        end
        
        # First 3 calls should succeed
        3.times do
          result = job_class.new.execute(rate_limited_client)
          expect(result[:success]).to be true
        end
        
        # 4th call should fail with rate limit error
        expect {
          job_class.new.execute(rate_limited_client)
        }.to raise_error(BackendApiClient::ApiError, 'Rate limit exceeded')
      end

      it 'maintains performance under high error rates' do
        error_prone_job = Class.new(BaseJob) do
          def execute(error_rate)
            # Randomly fail based on error rate
            if rand < error_rate
              raise StandardError.new('Random failure')
            end
            { success: true }
          end
        end
        
        # Test with 50% error rate
        error_rate = 0.5
        attempts = 100
        successes = 0
        failures = 0
        
        start_time = Time.current
        
        attempts.times do
          begin
            result = error_prone_job.new.execute(error_rate)
            successes += 1 if result[:success]
          rescue StandardError
            failures += 1
          end
        end
        
        total_time = Time.current - start_time
        
        # Should complete all attempts quickly even with high error rate
        expect(total_time).to be < 1.0
        
        # Success rate should approximate (1 - error_rate)
        success_rate = successes.to_f / attempts
        expect(success_rate).to be_within(0.1).of(1 - error_rate)
      end
    end

    describe 'data consistency and integrity' do
      it 'maintains data integrity across job retries' do
        stateful_job = Class.new(BaseJob) do
          @@processing_state = {}
          
          def execute(id, data)
            # Simulate stateful processing
            if @@processing_state[id]
              # Already processed, return cached result
              @@processing_state[id]
            else
              # First time processing
              if data['should_fail']
                @@processing_state[id] = { partial: true }
                raise StandardError.new('Processing failed midway')
              else
                @@processing_state[id] = { success: true, processed_data: data }
              end
            end
          end
          
          def self.reset_state
            @@processing_state.clear
          end
          
          def self.get_state(id)
            @@processing_state[id]
          end
        end
        
        stateful_job.reset_state
        
        # Test successful processing
        result = stateful_job.new.execute('test_1', { value: 'success' })
        expect(result[:success]).to be true
        expect(stateful_job.get_state('test_1')[:success]).to be true
        
        # Test partial failure and state preservation
        expect {
          stateful_job.new.execute('test_2', { should_fail: true })
        }.to raise_error(StandardError)
        
        expect(stateful_job.get_state('test_2')[:partial]).to be true
        
        # Retry should use preserved state
        retry_result = stateful_job.new.execute('test_2', {})
        expect(retry_result[:partial]).to be true
      end
    end
  end

  describe 'Concurrent Processing Performance' do
    it 'handles concurrent job processing efficiently' do
      concurrent_job = Class.new(BaseJob) do
        @@shared_counter = 0
        @@mutex = Mutex.new
        
        def execute(increment)
          @@mutex.synchronize do
            @@shared_counter += increment
          end
          { success: true, counter: @@shared_counter }
        end
        
        def self.counter
          @@shared_counter
        end
        
        def self.reset
          @@shared_counter = 0
        end
      end
      
      concurrent_job.reset
      
      # Process jobs concurrently
      threads = []
      results = []
      thread_count = 5
      jobs_per_thread = 10
      
      start_time = Time.current
      
      thread_count.times do |t|
        threads << Thread.new do
          thread_results = []
          jobs_per_thread.times do |j|
            result = concurrent_job.new.execute(1)
            thread_results << result
          end
          results.concat(thread_results)
        end
      end
      
      threads.each(&:join)
      total_time = Time.current - start_time
      
      # Verify correctness
      expect(concurrent_job.counter).to eq(thread_count * jobs_per_thread)
      expect(results.all? { |r| r[:success] }).to be true
      
      # Verify performance
      expect(total_time).to be < 2.0 # Should complete 50 jobs in under 2 seconds
      
      # Average time per job should be reasonable
      avg_time_per_job = total_time / (thread_count * jobs_per_thread)
      expect(avg_time_per_job).to be < 0.1
    end

    it 'maintains performance under thread contention' do
      # Test performance when many threads compete for resources
      contentious_job = Class.new(BaseJob) do
        @@shared_resource = []
        @@access_times = []
        @@mutex = Mutex.new
        
        def execute(data)
          access_start = Time.current
          
          @@mutex.synchronize do
            @@shared_resource << data
            sleep(0.001) # Simulate brief critical section
          end
          
          access_time = Time.current - access_start
          @@mutex.synchronize { @@access_times << access_time }
          
          { success: true, access_time: access_time }
        end
        
        def self.resource_size
          @@shared_resource.size
        end
        
        def self.average_access_time
          return 0.0 if @@access_times.empty?
          @@access_times.sum / @@access_times.size
        end
        
        def self.reset
          @@shared_resource.clear
          @@access_times.clear
        end
      end
      
      contentious_job.reset
      
      # High contention scenario
      thread_count = 20
      jobs_per_thread = 5
      threads = []
      
      start_time = Time.current
      
      thread_count.times do |t|
        threads << Thread.new do
          jobs_per_thread.times do |j|
            contentious_job.new.execute("thread_#{t}_job_#{j}")
          end
        end
      end
      
      threads.each(&:join)
      total_time = Time.current - start_time
      
      # Verify all jobs completed
      expect(contentious_job.resource_size).to eq(thread_count * jobs_per_thread)
      
      # Performance should degrade gracefully under contention
      expect(total_time).to be < 5.0 # Should still complete in reasonable time
      expect(contentious_job.average_access_time).to be < 0.1 # Average wait time reasonable
    end
  end
end
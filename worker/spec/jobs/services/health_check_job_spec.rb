# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Services::HealthCheckJob, type: :job do
  subject { described_class }

  let(:job_id) { 'health_check_job_123' }
  let(:environment) { 'production' }
  let(:specific_service) { 'redis' }
  let(:api_client_double) { double('BackendApiClient') }
  let(:job_instance) { subject.new }

  before do
    mock_powernode_worker_config
    allow(job_instance).to receive(:api_client).and_return(api_client_double)
  end

  it_behaves_like 'a base job', described_class
  it_behaves_like 'a job with API communication'
  it_behaves_like 'a job with retry logic'
  it_behaves_like 'a job with logging'
  it_behaves_like 'a job with timing metrics'

  describe 'job configuration' do
    it 'uses services queue' do
      expect(subject.sidekiq_options['queue']).to eq('services')
    end

    it 'has retry count of 1' do
      expect(subject.sidekiq_options['retry']).to eq(1)
    end
  end

  describe '#execute' do
    let(:health_check_response) do
      {
        'services' => {
          'redis' => { 'status' => 'healthy', 'response_time' => 5 },
          'database' => { 'status' => 'healthy', 'response_time' => 12 },
          'email_service' => { 'status' => 'degraded', 'response_time' => 250 },
          'payment_gateway' => { 'status' => 'unhealthy', 'response_time' => 5000 }
        }
      }
    end

    before do
      allow(api_client_double).to receive(:post).and_return(health_check_response)
      allow(api_client_double).to receive(:patch).and_return({ 'success' => true })
    end

    context 'with successful health check' do
      it 'performs health check via API' do
        job_instance.execute(environment, specific_service, job_id)
        
        expect(api_client_double).to have_received(:post).with(
          '/api/v1/internal/services/health_check',
          {
            environment: environment,
            service: specific_service
          }
        )
      end

      it 'returns comprehensive health check results' do
        freeze_time_at(Time.current) do
          result = job_instance.execute(environment, specific_service, job_id)
          
          expect(result).to include(
            job_id: job_id,
            status: 'completed',
            environment: environment,
            services: health_check_response['services'],
            healthy_count: 2,
            total_count: 4,
            overall_status: 'degraded'
          )
          expect(result[:duration]).to be_a(Float)
          expect(result[:message]).to eq('Health check completed: 2/4 services healthy')
        end
      end

      it 'calculates overall status correctly' do
        # All healthy
        all_healthy_response = {
          'services' => {
            'redis' => { 'status' => 'healthy' },
            'database' => { 'status' => 'healthy' }
          }
        }
        allow(api_client_double).to receive(:post).and_return(all_healthy_response)
        
        result = job_instance.execute
        expect(result[:overall_status]).to eq('healthy')
        
        # All unhealthy
        all_unhealthy_response = {
          'services' => {
            'redis' => { 'status' => 'unhealthy' },
            'database' => { 'status' => 'unhealthy' }
          }
        }
        allow(api_client_double).to receive(:post).and_return(all_unhealthy_response)
        
        result = job_instance.execute
        expect(result[:overall_status]).to eq('unhealthy')
      end

      it 'logs health check progress' do
        logger_double = mock_logger
        
        job_instance.execute(environment, specific_service, job_id)
        
        expect(logger_double).to have_received(:info).with(
          match(/Starting health checks.*#{job_id}.*#{environment}.*#{specific_service}/)
        )
        
        expect(logger_double).to have_received(:info).with(
          match(/Health check completed: 2\/4 healthy in \d+\.\d+s/)
        )
      end

      it 'updates job status when job_id provided' do
        result = job_instance.execute(environment, specific_service, job_id)
        
        expect(api_client_double).to have_received(:patch).with(
          "/api/v1/internal/jobs/#{job_id}",
          {
            status: 'completed',
            result: result
          }
        )
      end

      it 'works without job_id (no status update)' do
        result = job_instance.execute(environment, specific_service)
        
        expect(result[:job_id]).to be_nil
        expect(api_client_double).not_to have_received(:patch)
      end

      it 'handles default parameters' do
        result = job_instance.execute
        
        expect(result[:environment]).to eq('all')
        expect(api_client_double).to have_received(:post).with(
          '/api/v1/internal/services/health_check',
          {
            environment: nil,
            service: nil
          }
        )
      end
    end

    context 'with empty health check results' do
      before do
        allow(api_client_double).to receive(:post).and_return({ 'services' => {} })
      end

      it 'handles empty services list' do
        result = job_instance.execute
        
        expect(result).to include(
          healthy_count: 0,
          total_count: 0,
          overall_status: 'unknown'
        )
      end
    end

    context 'when health check API fails' do
      let(:api_error) { BackendApiClient::ApiError.new('Service unavailable', 503) }

      before do
        allow(api_client_double).to receive(:post).and_raise(api_error)
        allow(api_client_double).to receive(:patch).and_return({ 'success' => true })
      end

      it 'handles API errors gracefully' do
        logger_double = mock_logger
        
        expect {
          job_instance.execute(environment, specific_service, job_id)
        }.to raise_error(BackendApiClient::ApiError)
        
        expect(logger_double).to have_received(:error).with(
          match(/Health check failed after \d+\.\d+s: Service unavailable/)
        )
      end

      it 'updates job status as failed' do
        begin
          job_instance.execute(environment, specific_service, job_id)
        rescue BackendApiClient::ApiError
          # Expected
        end
        
        expect(api_client_double).to have_received(:patch).with(
          "/api/v1/internal/jobs/#{job_id}",
          hash_including(
            status: 'failed',
            result: hash_including(
              error: 'Service unavailable',
              message: 'Health check failed',
              status: 'failed'
            )
          )
        )
      end

      it 'tracks partial results before failure' do
        # Simulate API call that partially succeeds then fails
        call_count = 0
        allow(api_client_double).to receive(:post) do
          call_count += 1
          if call_count == 1
            # First call to get some data
            { 'services' => { 'redis' => { 'status' => 'healthy' } } }
          else
            raise api_error
          end
        end
        
        begin
          job_instance.execute(nil, nil, job_id)
        rescue BackendApiClient::ApiError
          # Expected
        end
        
        expect(api_client_double).to have_received(:patch).with(
          "/api/v1/internal/jobs/#{job_id}",
          hash_including(
            status: 'completed',
            result: hash_including(
              services: { 'redis' => { 'status' => 'healthy' } }
            )
          )
        )
      end
    end

    context 'when status update fails' do
      before do
        allow(api_client_double).to receive(:post).and_return(health_check_response)
        allow(api_client_double).to receive(:patch).and_raise(StandardError.new('Update failed'))
      end

      it 'logs warning but continues execution' do
        logger_double = mock_logger
        
        result = job_instance.execute(nil, nil, job_id)
        
        expect(result[:status]).to eq('completed')
        expect(logger_double).to have_received(:warn).with('Failed to update job status: Update failed')
      end
    end

    context 'with API retry mechanism' do
      it 'uses with_api_retry for health check call' do
        allow(job_instance).to receive(:with_api_retry).and_call_original
        
        job_instance.execute
        
        expect(job_instance).to have_received(:with_api_retry)
      end

      it 'retries on retryable API errors' do
        call_count = 0
        allow(api_client_double).to receive(:post) do
          call_count += 1
          if call_count < 2
            raise BackendApiClient::ApiError.new('Temporary failure', 503)
          else
            health_check_response
          end
        end
        
        result = job_instance.execute
        
        expect(result[:status]).to eq('completed')
        expect(call_count).to eq(2)
      end
    end
  end

  describe 'private methods' do
    describe '#calculate_overall_status' do
      it 'returns unknown for empty results' do
        status = job_instance.send(:calculate_overall_status, {})
        expect(status).to eq('unknown')
      end

      it 'returns healthy when all services healthy' do
        services = {
          'redis' => { 'status' => 'healthy' },
          'db' => { 'status' => 'healthy' }
        }
        
        status = job_instance.send(:calculate_overall_status, services)
        expect(status).to eq('healthy')
      end

      it 'returns degraded when some services healthy' do
        services = {
          'redis' => { 'status' => 'healthy' },
          'db' => { 'status' => 'unhealthy' }
        }
        
        status = job_instance.send(:calculate_overall_status, services)
        expect(status).to eq('degraded')
      end

      it 'returns unhealthy when no services healthy' do
        services = {
          'redis' => { 'status' => 'unhealthy' },
          'db' => { 'status' => 'down' }
        }
        
        status = job_instance.send(:calculate_overall_status, services)
        expect(status).to eq('unhealthy')
      end
    end

    describe '#update_job_status' do
      let(:result) { { status: 'completed', message: 'Test result' } }

      it 'updates job status via API' do
        allow(api_client_double).to receive(:patch).and_return({ 'updated' => true })
        
        job_instance.send(:update_job_status, job_id, result)
        
        expect(api_client_double).to have_received(:patch).with(
          "/api/v1/internal/jobs/#{job_id}",
          {
            status: 'completed',
            result: result
          }
        )
      end

      it 'handles update failures gracefully' do
        allow(api_client_double).to receive(:patch).and_raise(StandardError.new('Network error'))
        logger_double = mock_logger
        
        job_instance.send(:update_job_status, job_id, result)
        
        expect(logger_double).to have_received(:warn).with('Failed to update job status: Network error')
      end
    end
  end

  describe 'integration with Sidekiq' do
    it 'can be enqueued with parameters' do
      with_sidekiq_testing_mode(:fake) do
        described_class.perform_async(environment, specific_service, job_id)
        
        expect(described_class.jobs.size).to eq(1)
        job_args = described_class.jobs.first['args']
        expect(job_args).to eq([environment, specific_service, job_id])
      end
    end

    it 'uses services queue' do
      with_sidekiq_testing_mode(:fake) do
        described_class.perform_async(environment)
        
        expect_job_in_queue(described_class, 'services')
      end
    end
  end

  describe 'performance considerations' do
    let(:health_check_response) do
      {
        'services' => {
          'redis' => { 'status' => 'healthy', 'response_time' => 5 },
          'database' => { 'status' => 'healthy', 'response_time' => 12 }
        }
      }
    end

    before do
      allow(api_client_double).to receive(:post).and_return(health_check_response)
      allow(api_client_double).to receive(:patch).and_return({ 'success' => true })
    end

    it 'completes health check within reasonable time' do
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      
      result = job_instance.execute(environment)
      
      end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      duration = end_time - start_time
      
      expect(duration).to be < 5.0 # Should complete quickly due to mocking
      expect(result[:duration]).to be < 1.0 # Most time should be mocked
    end

    it 'tracks execution duration accurately' do
      # Override with slower health check
      allow(api_client_double).to receive(:post) do
        sleep(0.1) # Simulate API delay
        health_check_response
      end
      
      result = job_instance.execute
      
      expect(result[:duration]).to be >= 0.1
      expect(result[:duration]).to be < 0.5
    end
  end
end
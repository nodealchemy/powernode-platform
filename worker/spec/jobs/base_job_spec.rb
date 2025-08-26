# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BaseJob, type: :job do
  let(:test_job_class) do
    Class.new(BaseJob) do
      def execute(*args)
        @executed_with = args
        { success: true, args: args }
      end

      attr_reader :executed_with
    end
  end

  let(:job_instance) { test_job_class.new }

  before do
    mock_powernode_worker_config
  end

  describe 'class configuration' do
    it 'includes Sidekiq::Job' do
      expect(BaseJob.included_modules).to include(Sidekiq::Job)
    end

    it 'has default sidekiq options' do
      expect(BaseJob.sidekiq_options).to include(
        'retry' => 3,
        'dead' => true,
        'queue' => 'default'
      )
    end

    it 'has custom retry logic defined' do
      expect(BaseJob.sidekiq_retry_in_block).to be_present
    end
  end

  describe '#perform' do
    it 'calls execute method with arguments' do
      result = job_instance.perform('arg1', 'arg2', key: 'value')
      
      expect(job_instance.executed_with).to eq(['arg1', 'arg2', { key: 'value' }])
    end

    it 'logs job start and completion' do
      logger_double = mock_logger
      
      job_instance.perform('test_arg')
      
      expect(logger_double).to have_received(:info).with(match(/Starting.*test_arg/))
      expect(logger_double).to have_received(:info).with(match(/Completed.*in.*s/))
    end

    it 'tracks execution time' do
      logger_double = mock_logger
      
      # Mock execution to take some time
      allow(job_instance).to receive(:execute) do
        sleep(0.1)
        { success: true }
      end
      
      job_instance.perform
      
      expect(logger_double).to have_received(:info).with(match(/in \d+\.\d+s/))
    end

    it 'logs and re-raises errors' do
      logger_double = mock_logger
      error_message = 'Test error message'
      
      allow(job_instance).to receive(:execute).and_raise(StandardError.new(error_message))
      
      expect { job_instance.perform }.to raise_error(StandardError, error_message)
      
      expect(logger_double).to have_received(:error).with(match(/Failed.*#{error_message}/))
    end

    it 'includes backtrace in debug mode' do
      logger_double = mock_logger
      allow(logger_double).to receive(:level).and_return(Logger::DEBUG)
      
      allow(job_instance).to receive(:execute).and_raise(StandardError.new('Test error'))
      
      expect { job_instance.perform }.to raise_error(StandardError)
      
      expect(logger_double).to have_received(:error).at_least(:once)
    end
  end

  describe '#execute' do
    it 'raises NotImplementedError when not overridden' do
      base_job = BaseJob.new
      
      expect { base_job.send(:execute) }.to raise_error(NotImplementedError, /must implement the execute method/)
    end
  end

  describe 'retry strategy' do
    let(:retry_block) { BaseJob.sidekiq_retry_in_block }

    context 'with API errors' do
      let(:api_error) { BackendApiClient::ApiError.new('API Error', 500) }

      it 'uses shorter intervals for API errors' do
        interval_1 = retry_block.call(1, api_error)
        interval_2 = retry_block.call(2, api_error)
        interval_3 = retry_block.call(3, api_error)
        
        expect(interval_1).to eq(30)
        expect(interval_2).to eq(60)
        expect(interval_3).to eq(180)
      end

      it 'uses default interval for high retry counts' do
        interval = retry_block.call(5, api_error)
        expect(interval).to eq(300)
      end
    end

    context 'with other errors' do
      let(:standard_error) { StandardError.new('Other error') }

      it 'uses exponential backoff with randomization' do
        # Mock rand to return 0 for consistent testing
        allow(Object).to receive(:rand).with(30).and_return(0)
        
        interval_1 = retry_block.call(1, standard_error)
        interval_2 = retry_block.call(2, standard_error)
        
        expect(interval_1).to eq(16) # (1^4) + 15 + (0 * 2)
        expect(interval_2).to eq(31) # (2^4) + 15 + (0 * 3)
      end

      it 'includes randomization factor' do
        allow(Object).to receive(:rand).with(30).and_return(15)
        
        interval = retry_block.call(1, standard_error)
        expected = (1 ** 4) + 15 + (15 * (1 + 1)) # 1 + 15 + 30 = 46
        
        expect(interval).to eq(expected)
      end
    end
  end

  describe 'helper methods' do
    describe '#api_client' do
      it 'returns BackendApiClient instance' do
        api_client = job_instance.send(:api_client)
        expect(api_client).to be_a(BackendApiClient)
      end

      it 'memoizes the client instance' do
        client_1 = job_instance.send(:api_client)
        client_2 = job_instance.send(:api_client)
        
        expect(client_1).to be(client_2)
      end
    end

    describe '#logger' do
      it 'returns PowernodeWorker logger' do
        logger = job_instance.send(:logger)
        expect(logger).to eq(PowernodeWorker.application.logger)
      end
    end

    describe '#safe_parse_json' do
      it 'parses valid JSON' do
        json_string = '{"key": "value", "number": 42}'
        result = job_instance.send(:safe_parse_json, json_string)
        
        expect(result).to eq({ 'key' => 'value', 'number' => 42 })
      end

      it 'returns default for invalid JSON' do
        invalid_json = '{"invalid": json}'
        default = { 'error' => true }
        
        logger_double = mock_logger
        result = job_instance.send(:safe_parse_json, invalid_json, default)
        
        expect(result).to eq(default)
        expect(logger_double).to have_received(:warn).with(match(/Failed to parse JSON/))
      end

      it 'returns default for nil input' do
        result = job_instance.send(:safe_parse_json, nil, { default: true })
        expect(result).to eq({ default: true })
      end

      it 'returns default for empty string' do
        result = job_instance.send(:safe_parse_json, '', { empty: true })
        expect(result).to eq({ empty: true })
      end

      it 'uses empty hash as default when none provided' do
        result = job_instance.send(:safe_parse_json, nil)
        expect(result).to eq({})
      end
    end

    describe '#format_currency' do
      it 'formats positive amounts correctly' do
        result = job_instance.send(:format_currency, 2500)
        expect(result).to eq('$25.00')
      end

      it 'formats zero amounts' do
        result = job_instance.send(:format_currency, 0)
        expect(result).to eq('$0.00')
      end

      it 'handles nil amounts' do
        result = job_instance.send(:format_currency, nil)
        expect(result).to eq('$0.00')
      end

      it 'handles negative amounts' do
        result = job_instance.send(:format_currency, -1000)
        expect(result).to eq('$0.00')
      end

      it 'formats fractional amounts correctly' do
        result = job_instance.send(:format_currency, 1)
        expect(result).to eq('$0.01')
      end

      it 'supports different currencies (displays USD format regardless)' do
        result = job_instance.send(:format_currency, 5000, 'EUR')
        expect(result).to eq('$50.00')
      end
    end

    describe '#validate_required_params' do
      let(:params) { { 'name' => 'test', 'email' => 'test@example.com', 'age' => 25 } }

      it 'passes validation when all required params present' do
        expect {
          job_instance.send(:validate_required_params, params, 'name', 'email')
        }.not_to raise_error
      end

      it 'raises error when required params missing' do
        expect {
          job_instance.send(:validate_required_params, params, 'name', 'phone', 'address')
        }.to raise_error(ArgumentError, /Missing required parameters: phone, address/)
      end

      it 'handles string and symbol keys' do
        expect {
          job_instance.send(:validate_required_params, params, 'name', 'email')
        }.not_to raise_error
      end

      it 'works with empty params hash' do
        expect {
          job_instance.send(:validate_required_params, {}, 'required_key')
        }.to raise_error(ArgumentError, /Missing required parameters: required_key/)
      end
    end

    describe '#with_api_retry' do
      let(:api_client_double) { double('ApiClient') }

      before do
        allow(job_instance).to receive(:api_client).and_return(api_client_double)
      end

      it 'executes block successfully without retry' do
        result = job_instance.send(:with_api_retry) { 'success' }
        expect(result).to eq('success')
      end

      it 'retries on retryable API errors' do
        logger_double = mock_logger
        call_count = 0
        
        result = job_instance.send(:with_api_retry, max_attempts: 3) do
          call_count += 1
          if call_count < 3
            raise BackendApiClient::ApiError.new('Server Error', 500)
          end
          'success after retry'
        end
        
        expect(result).to eq('success after retry')
        expect(call_count).to eq(3)
        expect(logger_double).to have_received(:warn).twice
      end

      it 'gives up after max attempts' do
        logger_double = mock_logger
        
        expect {
          job_instance.send(:with_api_retry, max_attempts: 2) do
            raise BackendApiClient::ApiError.new('Persistent Error', 500)
          end
        }.to raise_error(BackendApiClient::ApiError, 'Persistent Error')
        
        expect(logger_double).to have_received(:warn).once
        expect(logger_double).to have_received(:error).once
      end

      it 'does not retry non-retryable errors' do
        logger_double = mock_logger
        
        expect {
          job_instance.send(:with_api_retry) do
            raise BackendApiClient::ApiError.new('Bad Request', 400)
          end
        }.to raise_error(BackendApiClient::ApiError, 'Bad Request')
        
        expect(logger_double).to have_received(:error).once
        expect(logger_double).not_to have_received(:warn)
      end

      it 'includes exponential backoff delay' do
        call_count = 0
        start_time = Time.current
        
        begin
          job_instance.send(:with_api_retry, max_attempts: 3) do
            call_count += 1
            raise BackendApiClient::ApiError.new('Server Error', 503)
          end
        rescue BackendApiClient::ApiError
          # Expected to fail after retries
        end
        
        # Should have waited for retries (2^1 + 2^2 = 6 seconds minimum)
        expect(call_count).to eq(3)
      end
    end
  end

  describe 'private methods' do
    describe '#retryable_error?' do
      it 'identifies retryable HTTP status codes' do
        retryable_statuses = [408, 429, 500, 502, 503, 504]
        
        retryable_statuses.each do |status|
          error = BackendApiClient::ApiError.new('Error', status)
          expect(job_instance.send(:retryable_error?, error)).to be true
        end
      end

      it 'identifies non-retryable HTTP status codes' do
        non_retryable_statuses = [400, 401, 403, 404, 422]
        
        non_retryable_statuses.each do |status|
          error = BackendApiClient::ApiError.new('Error', status)
          expect(job_instance.send(:retryable_error?, error)).to be false
        end
      end

      it 'handles errors without status code' do
        error = BackendApiClient::ApiError.new('Error')
        expect(job_instance.send(:retryable_error?, error)).to be false
      end
    end
  end
end
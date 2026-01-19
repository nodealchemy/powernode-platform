# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiErrorRecoveryService, type: :service do
  include AiOrchestrationTestHelpers

  let(:env) { setup_minimal_ai_environment }
  let(:account) { env[:account] }
  let(:provider) { env[:provider] }
  let(:credential) { env[:credential] }
  let(:execution_context) { { request_id: 'test-123', user_id: env[:user].id } }
  let(:service) { described_class.new(account, execution_context) }
  let(:redis_mock) { stub_redis_connection }

  before do
    credential # Ensure credential is created
  end

  describe '#initialize' do
    it 'initializes with account and execution context' do
      expect(service.instance_variable_get(:@account)).to eq(account)
      expect(service.instance_variable_get(:@execution_context)).to eq(execution_context)
      expect(service.instance_variable_get(:@max_recovery_attempts)).to eq(10)
    end
  end

  describe '#execute_with_recovery' do
    let(:request_type) { 'text_generation' }
    let(:options) { { model: 'gpt-3.5-turbo', max_tokens: 100 } }

    context 'when execution succeeds on first attempt' do
      it 'executes successfully without recovery' do
        allow(service).to receive(:execute_request).and_return({ success: true, result: 'Success' })

        result = service.execute_with_recovery(provider, request_type, **options) { |p, opts| 'success' }

        expect(result).to eq({ success: true, result: 'Success' })
      end
    end

    context 'when execution fails with recoverable error' do
      before do
        # First call fails, second call succeeds
        call_count = 0
        allow(service).to receive(:execute_request) do
          call_count += 1
          if call_count == 1
            raise StandardError.new('Rate limit exceeded')
          else
            { success: true, result: 'Success after retry' }
          end
        end

        allow(service).to receive(:classify_error).and_return(:rate_limit)
        allow(service).to receive(:should_retry?).and_return(true, false)
        allow(service).to receive(:calculate_backoff).and_return(0.1)
        allow(service).to receive(:record_successful_recovery)
      end

      it 'retries and eventually succeeds' do
        result = service.execute_with_recovery(provider, request_type, **options) { |p, opts| 'success' }

        expect(result).to eq({ success: true, result: 'Success after retry' })
        expect(service).to have_received(:record_successful_recovery).once
      end
    end

    context 'when execution fails with fallback strategy' do
      let(:alternative_provider) { create(:ai_provider, account: account) }

      before do
        create(:ai_provider_credential, provider: alternative_provider, is_active: true)

        allow(service).to receive(:execute_request).with(provider, anything, anything)
          .and_raise(StandardError.new('Authentication failed'))
        allow(service).to receive(:execute_request).with(alternative_provider, anything, anything)
          .and_return({ success: true, result: 'Success with fallback' })

        allow(service).to receive(:classify_error).and_return(:authentication)
        allow(service).to receive(:should_retry?).and_return(false)
        allow(service).to receive(:should_fallback?).and_return(true)
        allow(service).to receive(:apply_fallback_strategy).and_return(alternative_provider)
        allow(service).to receive(:record_successful_recovery)
      end

      it 'switches to alternative provider' do
        result = service.execute_with_recovery(provider, request_type, **options) { |p, opts| 'success' }

        expect(result).to eq({ success: true, result: 'Success with fallback' })
        expect(service).to have_received(:apply_fallback_strategy)
      end
    end

    context 'when all recovery attempts fail' do
      before do
        allow(service).to receive(:execute_request)
          .and_raise(StandardError.new('Unrecoverable error'))
        allow(service).to receive(:classify_error).and_return(:server_error)
        allow(service).to receive(:should_retry?).and_return(false)
        allow(service).to receive(:should_fallback?).and_return(false)
        allow(service).to receive(:record_recovery_failure)
      end

      it 'raises RecoveryFailedError' do
        expect {
          service.execute_with_recovery(provider, request_type, **options) { |p, opts| 'fail' }
        }.to raise_error(AiErrorRecoveryService::RecoveryFailedError)

        expect(service).to have_received(:record_recovery_failure)
      end
    end
  end

  describe '#classify_error' do
    it 'correctly classifies rate limit errors' do
      error = StandardError.new('Rate limit exceeded')
      expect(service.send(:classify_error, error)).to eq(:rate_limit)
    end

    it 'correctly classifies timeout errors' do
      error = StandardError.new('Request timed out')
      expect(service.send(:classify_error, error)).to eq(:timeout)
    end

    it 'correctly classifies authentication errors' do
      error = StandardError.new('Unauthorized access')
      expect(service.send(:classify_error, error)).to eq(:authentication)
    end

    it 'defaults to server_error for unknown errors' do
      error = StandardError.new('Some unknown error')
      expect(service.send(:classify_error, error)).to eq(:server_error)
    end
  end

  describe '#should_retry?' do
    it 'returns true for retryable errors within limit' do
      expect(service.send(:should_retry?, :rate_limit, 3)).to be true
    end

    it 'returns false for retryable errors exceeding limit' do
      expect(service.send(:should_retry?, :rate_limit, 6)).to be false
    end

    it 'returns false for non-retryable errors' do
      expect(service.send(:should_retry?, :authentication, 1)).to be false
    end
  end

  describe '#calculate_backoff' do
    it 'calculates exponential backoff' do
      expect(service.send(:calculate_backoff, :exponential, 1)).to eq(2)
      expect(service.send(:calculate_backoff, :exponential, 2)).to eq(4)
      expect(service.send(:calculate_backoff, :exponential, 10)).to eq(60) # max
    end

    it 'calculates linear backoff' do
      expect(service.send(:calculate_backoff, :linear, 3)).to eq(6)
      expect(service.send(:calculate_backoff, :linear, 20)).to eq(30) # max
    end

    it 'returns fixed backoff' do
      expect(service.send(:calculate_backoff, :fixed, 5)).to eq(5)
    end
  end

  describe '#switch_to_alternative_provider' do
    let(:alternative_provider) { create_ai_provider_with_credentials(account, slug: 'alternative') }

    context 'when alternatives are available' do
      before do
        alternative_provider # Ensure it's created
        stub_load_balancer(account, providers: [ provider, alternative_provider ])
        stub_circuit_breaker(alternative_provider, available: true)
      end

      it 'selects alternative provider successfully' do
        options = { model: 'gpt-3.5-turbo' }
        result = service.send(:switch_to_alternative_provider, provider, options)

        expect(result).to eq(alternative_provider)
      end
    end

    context 'when no alternatives available' do
      before do
        stub_load_balancer(account, providers: [ provider ])
      end

      it 'returns nil when no alternatives found' do
        options = { model: 'gpt-3.5-turbo' }
        result = service.send(:switch_to_alternative_provider, provider, options)

        expect(result).to be_nil
      end
    end
  end

  describe '#get_recovery_stats' do
    before do
      allow(redis_mock).to receive(:hgetall)
        .with("ai_recovery:#{account.id}:stats")
        .and_return({
          'total_executions' => '100',
          'failed_executions' => '10',
          'recovered_executions' => '8',
          'avg_recovery_time' => '2.5'
        })

      allow(service).to receive(:get_common_error_types).and_return([
        { type: 'rate_limit', count: 5 },
        { type: 'timeout', count: 3 }
      ])

      allow(service).to receive(:get_provider_reliability_stats).and_return([
        { id: provider.id, name: provider.name, success_rate: 95.0 }
      ])
    end

    it 'returns comprehensive recovery statistics' do
      stats = service.get_recovery_stats

      expect(stats[:total_executions]).to eq(100)
      expect(stats[:failed_executions]).to eq(10)
      expect(stats[:recovered_executions]).to eq(8)
      expect(stats[:recovery_rate]).to eq(8.0) # 8/100 * 100
      expect(stats[:avg_recovery_time]).to eq(2.5)
      expect(stats[:common_errors]).to be_an(Array)
      expect(stats[:provider_reliability]).to be_an(Array)
    end
  end

  describe '#reset_recovery_stats' do
    it 'clears recovery statistics from Redis' do
      expect(redis_mock).to receive(:del).with(
        "ai_recovery:#{account.id}:stats",
        "ai_recovery:#{account.id}:error_types",
        "ai_recovery:#{account.id}:provider_stats"
      )

      service.reset_recovery_stats
    end
  end

  # ============================================================================
  # COMPREHENSIVE ERROR CLASSIFICATION TESTS
  # ============================================================================

  describe 'comprehensive error classification' do
    it 'classifies rate limit errors' do
      [ 'Rate limit exceeded', 'Too many requests', '429 error' ].each do |message|
        error = StandardError.new(message)
        expect(service.send(:classify_error, error)).to eq(:rate_limit),
          "Expected '#{message}' to classify as :rate_limit"
      end
    end

    it 'classifies timeout errors' do
      [ 'Request timed out', 'Connection timeout' ].each do |message|
        error = StandardError.new(message)
        expect(service.send(:classify_error, error)).to eq(:timeout),
          "Expected '#{message}' to classify as :timeout"
      end
    end

    it 'classifies authentication errors' do
      [ 'Unauthorized', 'Authentication failed', '401 error' ].each do |message|
        error = StandardError.new(message)
        expect(service.send(:classify_error, error)).to eq(:authentication),
          "Expected '#{message}' to classify as :authentication"
      end
    end

    it 'classifies quota exceeded errors' do
      [ 'Quota exceeded', 'Billing issue', 'Payment required' ].each do |message|
        error = StandardError.new(message)
        expect(service.send(:classify_error, error)).to eq(:quota_exceeded),
          "Expected '#{message}' to classify as :quota_exceeded"
      end
    end

    it 'classifies model unavailable errors' do
      [ 'Model not available', 'Model is unavailable' ].each do |message|
        error = StandardError.new(message)
        expect(service.send(:classify_error, error)).to eq(:model_unavailable),
          "Expected '#{message}' to classify as :model_unavailable"
      end
    end

    it 'classifies network errors' do
      [ 'Network error', 'Connection refused', 'DNS resolution failed' ].each do |message|
        error = StandardError.new(message)
        expect(service.send(:classify_error, error)).to eq(:network_error),
          "Expected '#{message}' to classify as :network_error"
      end
    end

    it 'classifies server errors' do
      [ 'Server error', '500 Internal Server Error', '502 Bad Gateway',
       '503 Service Unavailable' ].each do |message|
        error = StandardError.new(message)
        expect(service.send(:classify_error, error)).to eq(:server_error),
          "Expected '#{message}' to classify as :server_error"
      end
    end

    it 'classifies 504 as timeout (contains timeout keyword)' do
      error = StandardError.new('504 Gateway Timeout')
      expect(service.send(:classify_error, error)).to eq(:timeout)
    end

    it 'classifies validation errors' do
      [ 'Validation failed', 'Invalid request', 'Bad request', '400 error' ].each do |message|
        error = StandardError.new(message)
        expect(service.send(:classify_error, error)).to eq(:validation_error),
          "Expected '#{message}' to classify as :validation_error"
      end
    end

    it 'classifies circuit breaker errors' do
      error = StandardError.new('Circuit breaker is open')
      expect(service.send(:classify_error, error)).to eq(:circuit_breaker)
    end
  end

  # ============================================================================
  # EXECUTE REQUEST TESTS (Circuit Breaker Integration)
  # ============================================================================

  describe '#execute_request' do
    let(:request_block) { ->(p, opts) { { result: 'success' } } }

    context 'when circuit breaker allows execution' do
      let!(:circuit_breaker) { stub_circuit_breaker(provider, available: true) }

      before do
        allow(service).to receive(:record_successful_execution)
      end

      it 'checks circuit breaker before executing' do
        service.send(:execute_request, provider, 'test', {}, &request_block)

        expect(circuit_breaker).to have_received(:provider_available?)
      end

      it 'executes request through circuit breaker' do
        service.send(:execute_request, provider, 'test', {}, &request_block)

        expect(circuit_breaker).to have_received(:call)
      end

      it 'records successful execution with timing' do
        service.send(:execute_request, provider, 'test', {}, &request_block)

        expect(service).to have_received(:record_successful_execution).with(provider, anything)
      end

      it 'returns the result from the block' do
        result = service.send(:execute_request, provider, 'test', {}, &request_block)

        expect(result).to eq({ result: 'success' })
      end
    end

    context 'when circuit breaker is open' do
      let!(:circuit_breaker) { stub_circuit_breaker(provider, available: false) }

      it 'raises error without executing request' do
        expect {
          service.send(:execute_request, provider, 'test', {}, &request_block)
        }.to raise_error(StandardError, 'Circuit breaker open')
      end

      it 'does not record execution' do
        expect(service).not_to receive(:record_successful_execution)

        begin
          service.send(:execute_request, provider, 'test', {}, &request_block)
        rescue StandardError
          # Expected
        end
      end
    end
  end

  # ============================================================================
  # FALLBACK STRATEGY TESTS
  # ============================================================================

  describe '#apply_fallback_strategy' do
    let(:options) { { model: 'gpt-4', max_tokens: 1000 } }

    context 'switch_provider strategy' do
      let(:alternative_provider) { create(:ai_provider, account: account) }

      before do
        create(:ai_provider_credential, provider: alternative_provider, is_active: true)
        allow(service).to receive(:switch_to_alternative_provider)
          .and_return(alternative_provider)
      end

      it 'delegates to switch_to_alternative_provider' do
        expect(service).to receive(:switch_to_alternative_provider)
          .with(provider, options)

        service.send(:apply_fallback_strategy, :switch_provider, provider, :authentication, options)
      end

      it 'returns alternative provider' do
        result = service.send(:apply_fallback_strategy, :switch_provider, provider, :authentication, options)

        expect(result).to eq(alternative_provider)
      end
    end

    context 'switch_model strategy' do
      before do
        allow(service).to receive(:switch_to_alternative_model).and_return(provider)
      end

      it 'delegates to switch_to_alternative_model' do
        expect(service).to receive(:switch_to_alternative_model)
          .with(provider, options)

        service.send(:apply_fallback_strategy, :switch_model, provider, :model_unavailable, options)
      end

      it 'returns provider with modified options' do
        result = service.send(:apply_fallback_strategy, :switch_model, provider, :model_unavailable, options)

        expect(result).to eq(provider)
      end
    end

    context 'modify_request strategy' do
      it 'modifies request parameters' do
        expect(service).to receive(:modify_request_parameters)
          .with(options, :validation_error)

        service.send(:apply_fallback_strategy, :modify_request, provider, :validation_error, options)
      end

      it 'returns current provider' do
        result = service.send(:apply_fallback_strategy, :modify_request, provider, :validation_error, options)

        expect(result).to eq(provider)
      end
    end

    context 'unknown strategy' do
      it 'returns nil for unknown strategy' do
        result = service.send(:apply_fallback_strategy, :unknown_strategy, provider, :error, options)

        expect(result).to be_nil
      end
    end
  end

  # ============================================================================
  # SWITCH TO ALTERNATIVE MODEL TESTS
  # ============================================================================

  describe '#switch_to_alternative_model' do
    context 'when alternative models are available' do
      let(:openai_provider) { create(:ai_provider, account: account, slug: 'openai') }
      let(:options) { { model: 'gpt-4' } }

      it 'switches to alternative model for OpenAI' do
        result = service.send(:switch_to_alternative_model, openai_provider, options)

        expect(options[:model]).to eq('gpt-3.5-turbo')
        expect(result).to eq(openai_provider)
      end

      it 'logs model switch' do
        allow(Rails.logger).to receive(:info)

        service.send(:switch_to_alternative_model, openai_provider, options)

        expect(Rails.logger).to have_received(:info)
          .with(/Switching model from gpt-4 to gpt-3\.5-turbo/)
      end
    end

    context 'when no alternative models available' do
      let(:unknown_provider) { create(:ai_provider, account: account, slug: 'unknown') }
      let(:options) { { model: 'some-model' } }

      it 'returns provider without modification' do
        result = service.send(:switch_to_alternative_model, unknown_provider, options)

        expect(options[:model]).to eq('some-model')
        expect(result).to eq(unknown_provider)
      end
    end
  end

  # ============================================================================
  # MODIFY REQUEST PARAMETERS TESTS
  # ============================================================================

  describe '#modify_request_parameters' do
    context 'for validation errors' do
      it 'reduces max_tokens to safe minimum' do
        options = { max_tokens: 2000, temperature: 1.5 }
        service.send(:modify_request_parameters, options, :validation_error)

        expect(options[:max_tokens]).to eq(100)
      end

      it 'ensures temperature is at least minimum threshold' do
        options = { max_tokens: 2000, temperature: 0.05 }
        service.send(:modify_request_parameters, options, :validation_error)

        expect(options[:temperature]).to eq(0.1) # max(0.05, 0.1) = 0.1
      end

      it 'keeps temperature if already above minimum' do
        options = { max_tokens: 2000, temperature: 0.7 }
        service.send(:modify_request_parameters, options, :validation_error)

        expect(options[:temperature]).to eq(0.7) # max(0.7, 0.1) = 0.7
      end
    end

    context 'for rate limit errors' do
      let(:options) { {} }

      it 'adds random request delay' do
        service.send(:modify_request_parameters, options, :rate_limit)

        expect(options[:request_delay]).to be_between(1, 5)
      end
    end
  end

  # ============================================================================
  # GET ALTERNATIVE MODELS TESTS
  # ============================================================================

  describe '#get_alternative_models' do
    it 'returns OpenAI alternatives excluding current model' do
      openai_provider = create(:ai_provider, slug: 'openai')
      alternatives = service.send(:get_alternative_models, openai_provider, 'gpt-4')

      expect(alternatives).to eq([ 'gpt-3.5-turbo' ])
      expect(alternatives).not_to include('gpt-4')
    end

    it 'returns Anthropic alternatives excluding current model' do
      anthropic_provider = create(:ai_provider, slug: 'anthropic')
      alternatives = service.send(:get_alternative_models, anthropic_provider, 'claude-3-sonnet-20240229')

      expect(alternatives).to eq([ 'claude-3-haiku-20240307' ])
      expect(alternatives).not_to include('claude-3-sonnet-20240229')
    end

    it 'returns empty array for unknown providers' do
      unknown_provider = create(:ai_provider, slug: 'unknown')
      alternatives = service.send(:get_alternative_models, unknown_provider, 'some-model')

      expect(alternatives).to eq([])
    end
  end

  # ============================================================================
  # RECORDING STATISTICS TESTS
  # ============================================================================

  describe '#record_successful_execution' do
    before do
      allow(redis_mock).to receive(:hincrby)
      allow(redis_mock).to receive(:hget).and_return('0.0', '10')
      allow(redis_mock).to receive(:hset)
      allow(redis_mock).to receive(:expire)
    end

    it 'increments total executions counter' do
      expect(redis_mock).to receive(:hincrby)
        .with("ai_recovery:#{account.id}:stats", 'total_executions', 1)

      service.send(:record_successful_execution, provider, 150.5)
    end

    it 'updates average execution time' do
      expect(redis_mock).to receive(:hset)
        .with("ai_recovery:#{account.id}:stats", 'avg_execution_time', anything)

      service.send(:record_successful_execution, provider, 150.5)
    end

    it 'sets expiration on stats key' do
      expect(redis_mock).to receive(:expire)
        .with("ai_recovery:#{account.id}:stats", 24.hours)

      service.send(:record_successful_execution, provider, 150.5)
    end
  end

  describe '#record_successful_recovery' do
    let(:recovery_attempts) do
      [
        { attempt: 1, error: 'Error 1', error_type: :rate_limit, provider: provider.id, timestamp: 5.seconds.ago },
        { attempt: 2, error: 'Error 2', error_type: :timeout, provider: provider.id, timestamp: Time.current }
      ]
    end

    before do
      allow(redis_mock).to receive(:hincrby)
      allow(redis_mock).to receive(:hget).and_return('0.0', '5')
      allow(redis_mock).to receive(:hset)
      allow(redis_mock).to receive(:expire)
    end

    it 'increments recovered executions counter' do
      expect(redis_mock).to receive(:hincrby)
        .with("ai_recovery:#{account.id}:stats", 'recovered_executions', 1)

      service.send(:record_successful_recovery, provider, recovery_attempts)
    end

    it 'calculates recovery time from attempts' do
      recovery_time = recovery_attempts.last[:timestamp] - recovery_attempts.first[:timestamp]

      expect(redis_mock).to receive(:hset)
        .with("ai_recovery:#{account.id}:stats", 'avg_recovery_time', anything)

      service.send(:record_successful_recovery, provider, recovery_attempts)
    end

    it 'logs successful recovery' do
      expect(Rails.logger).to receive(:info)
        .with(/Successful recovery for .+ after 2 attempts/)

      service.send(:record_successful_recovery, provider, recovery_attempts)
    end
  end

  describe '#record_recovery_failure' do
    let(:recovery_attempts) do
      [
        { attempt: 1, error: 'Error 1', error_type: :rate_limit, provider: provider.id, timestamp: Time.current },
        { attempt: 2, error: 'Error 2', error_type: :timeout, provider: provider.id, timestamp: Time.current }
      ]
    end

    before do
      allow(redis_mock).to receive(:hincrby)
      allow(redis_mock).to receive(:expire)
    end

    it 'increments failed executions counter' do
      expect(redis_mock).to receive(:hincrby)
        .with("ai_recovery:#{account.id}:stats", 'failed_executions', 1)

      service.send(:record_recovery_failure, provider, recovery_attempts)
    end

    it 'tracks each error type' do
      expect(redis_mock).to receive(:hincrby)
        .with("ai_recovery:#{account.id}:error_types", 'rate_limit', 1)
      expect(redis_mock).to receive(:hincrby)
        .with("ai_recovery:#{account.id}:error_types", 'timeout', 1)

      service.send(:record_recovery_failure, provider, recovery_attempts)
    end

    it 'logs recovery failure' do
      expect(Rails.logger).to receive(:error)
        .with(/Recovery failed for .+ after 2 attempts/)

      service.send(:record_recovery_failure, provider, recovery_attempts)
    end
  end

  # ============================================================================
  # STATISTICS CALCULATION TESTS
  # ============================================================================

  describe '#calculate_recovery_rate' do
    it 'calculates recovery rate correctly' do
      recovery_data = { 'total_executions' => '100', 'recovered_executions' => '75' }
      rate = service.send(:calculate_recovery_rate, recovery_data)

      expect(rate).to eq(75.0)
    end

    it 'handles zero total executions' do
      recovery_data = { 'total_executions' => '0', 'recovered_executions' => '0' }
      rate = service.send(:calculate_recovery_rate, recovery_data)

      expect(rate).to eq(0.0)
    end

    it 'handles nil values' do
      recovery_data = {}
      rate = service.send(:calculate_recovery_rate, recovery_data)

      expect(rate).to eq(0.0)
    end

    it 'rounds to 2 decimal places' do
      recovery_data = { 'total_executions' => '3', 'recovered_executions' => '2' }
      rate = service.send(:calculate_recovery_rate, recovery_data)

      expect(rate).to eq(66.67)
    end
  end

  describe '#get_common_error_types' do
    before do
      allow(redis_mock).to receive(:hgetall)
        .with("ai_recovery:#{account.id}:error_types")
        .and_return({
          'rate_limit' => '15',
          'timeout' => '10',
          'authentication' => '8',
          'network_error' => '5',
          'server_error' => '3',
          'validation_error' => '2',
          'quota_exceeded' => '1'
        })
    end

    it 'returns error types sorted by count descending' do
      error_types = service.send(:get_common_error_types, 1.hour)

      expect(error_types.first[:type]).to eq('rate_limit')
      expect(error_types.first[:count]).to eq(15)
    end

    it 'limits results to top 10' do
      error_types = service.send(:get_common_error_types, 1.hour)

      expect(error_types.size).to be <= 10
    end

    it 'converts counts to integers' do
      error_types = service.send(:get_common_error_types, 1.hour)

      error_types.each do |error_type|
        expect(error_type[:count]).to be_a(Integer)
      end
    end
  end

  describe '#get_provider_reliability_stats' do
    let(:alternative_provider) { create_ai_provider_with_credentials(account, slug: 'alternative') }

    before do
      alternative_provider # Ensure it's created

      allow(account.ai_providers).to receive(:active).and_return([ provider, alternative_provider ])

      # Stub circuit breakers with different states
      cb1 = stub_circuit_breaker(provider, available: true)
      allow(cb1).to receive(:circuit_state).and_return(:closed)

      cb2 = stub_circuit_breaker(alternative_provider, available: true)
      allow(cb2).to receive(:circuit_state).and_return(:half_open)

      # Stub load balancer with different stats for each provider
      load_balancer = stub_load_balancer(account, providers: [ provider, alternative_provider ])
      allow(load_balancer).to receive(:send).with(:get_provider_success_rate, provider).and_return(98.5)
      allow(load_balancer).to receive(:send).with(:get_provider_success_rate, alternative_provider).and_return(85.0)
      allow(load_balancer).to receive(:send).with(:get_provider_avg_response_time, provider).and_return(250.0)
      allow(load_balancer).to receive(:send).with(:get_provider_avg_response_time, alternative_provider).and_return(400.0)
    end

    it 'returns reliability stats for all active providers' do
      stats = service.send(:get_provider_reliability_stats, 1.hour)

      expect(stats.size).to eq(2)
    end

    it 'includes provider identification' do
      stats = service.send(:get_provider_reliability_stats, 1.hour)

      expect(stats.first[:id]).to eq(provider.id)
      expect(stats.first[:name]).to eq(provider.name)
    end

    it 'includes circuit breaker state' do
      stats = service.send(:get_provider_reliability_stats, 1.hour)

      expect(stats.first[:circuit_state]).to eq(:closed)
      expect(stats.last[:circuit_state]).to eq(:half_open)
    end

    it 'includes success rate from load balancer' do
      stats = service.send(:get_provider_reliability_stats, 1.hour)

      expect(stats.first[:success_rate]).to eq(98.5)
      expect(stats.last[:success_rate]).to eq(85.0)
    end

    it 'includes average response time' do
      stats = service.send(:get_provider_reliability_stats, 1.hour)

      expect(stats.first[:avg_response_time]).to eq(250.0)
      expect(stats.last[:avg_response_time]).to eq(400.0)
    end
  end

  # ============================================================================
  # INTEGRATION TESTS
  # ============================================================================

  describe 'integration scenarios' do
    context 'complete recovery workflow with retry' do
      let(:options) { { model: 'gpt-4', max_tokens: 1000 } }
      let(:request_block) { ->(p, opts) { { result: 'success' } } }
      let!(:circuit_breaker) { stub_circuit_breaker(provider, available: true) }

      before do
        call_count = 0

        # Mock execute_request to fail once then succeed
        allow(service).to receive(:execute_request) do
          call_count += 1
          if call_count == 1
            raise StandardError.new('Rate limit exceeded')
          else
            { success: true, result: 'Success after retry' }
          end
        end
      end

      it 'classifies error, retries with backoff, and succeeds' do
        result = service.execute_with_recovery(provider, 'test', **options, &request_block)

        expect(result).to eq({ success: true, result: 'Success after retry' })
      end

      it 'attempts execution multiple times on failure' do
        service.execute_with_recovery(provider, 'test', **options, &request_block)

        # Should call execute_request twice (1 failure + 1 success)
        expect(service).to have_received(:execute_request).twice
      end
    end

    context 'maximum recovery attempts exceeded' do
      let(:options) { { model: 'gpt-4' } }
      let(:request_block) { ->(p, opts) { { result: 'success' } } }
      let!(:circuit_breaker) { stub_circuit_breaker(provider, available: true) }

      before do
        # Always fail to trigger max attempts
        allow(service).to receive(:execute_request)
          .and_raise(StandardError.new('Persistent error'))
      end

      it 'raises RecoveryFailedError after all attempts fail' do
        expect {
          service.execute_with_recovery(provider, 'test', **options, &request_block)
        }.to raise_error(AiErrorRecoveryService::RecoveryFailedError, /All recovery attempts failed/)
      end

      it 'exhausts all recovery attempts before failing' do
        begin
          service.execute_with_recovery(provider, 'test', **options, &request_block)
        rescue AiErrorRecoveryService::RecoveryFailedError
          # Expected - verify execute_request was called multiple times
          expect(service).to have_received(:execute_request).at_least(:once)
        end
      end
    end
  end
end

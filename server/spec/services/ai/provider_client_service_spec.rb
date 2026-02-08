# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::ProviderClientService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:openai_provider) { create(:ai_provider, :openai) }
  let(:anthropic_provider) { create(:ai_provider, :anthropic) }
  let(:ollama_provider) { create(:ai_provider, :ollama) }
  let(:openai_credential) { create(:ai_provider_credential, account: account, provider: openai_provider) }
  let(:anthropic_credential) { create(:ai_provider_credential, account: account, provider: anthropic_provider) }
  let(:ollama_credential) do
    create(:ai_provider_credential, account: account, provider: ollama_provider,
           credentials: { 'base_url' => 'http://localhost:11434', 'model' => 'llama2' })
  end

  describe '#initialize' do
    it 'initializes with credential' do
      service = described_class.new(openai_credential)
      expect(service.credential).to eq(openai_credential)
      expect(service.provider).to eq(openai_provider)
    end

    it 'initializes rate limiting tracking' do
      service = described_class.new(openai_credential)
      expect(service.instance_variable_get(:@rate_limit_tracker)).to be_a(Hash)
    end

    it 'initializes circuit breaker' do
      service = described_class.new(openai_credential)
      # Circuit breaker is managed by Ai::ProviderCircuitBreakerService
      expect(service.instance_variable_get(:@circuit_breaker)).to be_a(Ai::ProviderCircuitBreakerService)
    end
  end

  describe '#send_message' do
    let(:service) { described_class.new(openai_credential) }
    let(:messages) { [ { role: 'user', content: 'Hello, AI!' } ] }
    let(:options) { { model: 'gpt-3.5-turbo', temperature: 0.7, max_tokens: 150 } }

    context 'successful requests' do
      before do
        stub_successful_openai_response
      end

      it 'sends message and returns response' do
        result = service.send_message(messages, options)

        expect(result).to be_a(Hash)
        expect(result[:success]).to be true
        expect(result[:response]).to include(:choices)
        expect(result[:response][:choices]).to be_an(Array)
        expect(result[:metadata]).to include(:tokens_used, :response_time_ms, :model_used)
      end

      it 'tracks token usage' do
        result = service.send_message(messages, options)

        expect(result[:metadata][:tokens_used]).to be > 0
        expect(result[:metadata][:tokens_used]).to be_a(Integer)
      end

      it 'records response time' do
        result = service.send_message(messages, options)

        expect(result[:metadata][:response_time_ms]).to be > 0
        expect(result[:metadata][:response_time_ms]).to be_a(Numeric)
      end

      it 'includes model information' do
        result = service.send_message(messages, options)

        expect(result[:metadata][:model_used]).to eq('gpt-3.5-turbo')
      end

      it 'handles custom parameters correctly' do
        custom_options = options.merge(temperature: 0.9, presence_penalty: 0.6)
        result = service.send_message(messages, custom_options)

        expect(result[:success]).to be true
        expect(result[:metadata][:parameters_used]).to include(
          temperature: 0.9,
          presence_penalty: 0.6
        )
      end
    end

    context 'OpenAI-specific requests' do
      let(:service) { described_class.new(openai_credential) }

      before do
        stub_successful_openai_response
      end

      it 'formats OpenAI request correctly' do
        service.send_message(messages, options)

        expect(WebMock).to have_requested(:post, 'https://api.openai.com/v1/chat/completions')
          .with(
            headers: {
              'Authorization' => /Bearer/,
              'Content-Type' => 'application/json'
            }
          )
      end

      it 'handles streaming requests' do
        result = service.send_message(messages, options.merge(stream: true))
        expect(result[:success]).to be true
        expect(result[:metadata][:stream_enabled]).to be true
      end

      it 'supports function calling' do
        function_options = options.merge(
          functions: [
            {
              name: 'get_weather',
              description: 'Get current weather',
              parameters: {
                type: 'object',
                properties: {
                  location: { type: 'string' }
                }
              }
            }
          ]
        )

        result = service.send_message(messages, function_options)
        expect(result[:success]).to be true
      end
    end

    context 'Anthropic-specific requests' do
      let(:service) { described_class.new(anthropic_credential) }

      before do
        stub_successful_anthropic_response
      end

      it 'formats Anthropic request correctly' do
        service.send_message(messages, { model: 'claude-3-sonnet-20240229', max_tokens: 150 })

        expect(WebMock).to have_requested(:post, 'https://api.anthropic.com/v1/messages')
          .with(
            headers: {
              'Content-Type' => 'application/json',
              'anthropic-version' => '2023-06-01'
            }
          )
      end

      it 'handles system messages correctly' do
        system_messages = [
          { role: 'system', content: 'You are a helpful assistant.' },
          { role: 'user', content: 'Hello!' }
        ]

        result = service.send_message(system_messages, { model: 'claude-3-sonnet-20240229', max_tokens: 100 })
        expect(result[:success]).to be true
      end
    end

    context 'Ollama-specific requests' do
      let(:service) { described_class.new(ollama_credential) }

      before do
        stub_successful_ollama_response
      end

      it 'formats Ollama request correctly' do
        service.send_message(messages, { model: 'llama2', stream: false })

        expect(WebMock).to have_requested(:post, 'http://localhost:11434/api/chat')
          .with(
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'uses custom base URL if provided' do
        stub_request(:post, 'http://custom-host:11434/api/chat')
          .to_return(status: 200, body: { message: { role: 'assistant', content: 'Hello' }, model: 'llama2' }.to_json)

        custom_ollama_credential = create(:ai_provider_credential,
          account: account,
          provider: ollama_provider,
          credentials: { 'base_url' => 'http://custom-host:11434', 'model' => 'llama2' }
        )

        service = described_class.new(custom_ollama_credential)
        service.send_message(messages, { model: 'llama2' })

        expect(WebMock).to have_requested(:post, 'http://custom-host:11434/api/chat')
      end
    end

    context 'error handling' do
      let(:service) { described_class.new(openai_credential) }

      it 'handles rate limiting' do
        stub_request(:post, 'https://api.openai.com/v1/chat/completions')
          .to_return(status: 429, body: '{"error": {"code": "rate_limit_exceeded"}}')

        result = service.send_message(messages, options)

        expect(result[:success]).to be false
        expect(result[:error]).to include('rate_limit_exceeded')
        expect(result[:retry_after]).to be_present
      end

      it 'handles authentication errors' do
        stub_request(:post, 'https://api.openai.com/v1/chat/completions')
          .to_return(status: 401, body: '{"error": {"code": "invalid_api_key"}}')

        result = service.send_message(messages, options)

        expect(result[:success]).to be false
        expect(result[:error]).to include('invalid_api_key')
        expect(result[:error_type]).to eq('authentication_error')
      end

      it 'handles quota exceeded errors' do
        stub_request(:post, 'https://api.openai.com/v1/chat/completions')
          .to_return(status: 429, body: '{"error": {"code": "quota_exceeded"}}')

        result = service.send_message(messages, options)

        expect(result[:success]).to be false
        expect(result[:error_type]).to eq('quota_exceeded')
      end

      it 'handles network timeouts' do
        stub_request(:post, 'https://api.openai.com/v1/chat/completions')
          .to_timeout

        result = service.send_message(messages, options)

        expect(result[:success]).to be false
        expect(result[:error_type]).to eq('network_error')
        expect(result[:error]).to include('timeout')
      end

      it 'handles malformed responses' do
        stub_request(:post, 'https://api.openai.com/v1/chat/completions')
          .to_return(status: 200, body: 'invalid json', headers: { 'Content-Type' => 'text/plain' })

        result = service.send_message(messages, options)

        expect(result[:success]).to be false
        # HTTParty may not parse as JSON, so the error type could vary
        expect(result[:error_type]).to be_in([ 'parse_error', 'api_error', 'unknown_error' ])
      end

      it 'handles server errors' do
        stub_request(:post, 'https://api.openai.com/v1/chat/completions')
          .to_return(status: 500, body: '{"error": "Internal server error"}')

        result = service.send_message(messages, options)

        expect(result[:success]).to be false
        expect(result[:error_type]).to eq('server_error')
        expect(result[:retry_recommended]).to be true
      end
    end
  end

  describe '#validate_message_format' do
    let(:service) { described_class.new(openai_credential) }

    it 'validates correct message format' do
      valid_messages = [
        { role: 'system', content: 'You are helpful.' },
        { role: 'user', content: 'Hello!' },
        { role: 'assistant', content: 'Hi there!' }
      ]

      expect { service.send(:validate_message_format, valid_messages) }.not_to raise_error
    end

    it 'rejects messages without role' do
      invalid_messages = [ { content: 'Hello!' } ]

      expect {
        service.send(:validate_message_format, invalid_messages)
      }.to raise_error(Ai::ProviderClientService::ValidationError, /role is required/)
    end

    it 'rejects messages without content' do
      invalid_messages = [ { role: 'user' } ]

      expect {
        service.send(:validate_message_format, invalid_messages)
      }.to raise_error(Ai::ProviderClientService::ValidationError, /content is required/)
    end

    it 'rejects invalid roles' do
      invalid_messages = [ { role: 'invalid', content: 'Hello!' } ]

      expect {
        service.send(:validate_message_format, invalid_messages)
      }.to raise_error(Ai::ProviderClientService::ValidationError, /Invalid role/)
    end

    it 'rejects empty message arrays' do
      expect {
        service.send(:validate_message_format, [])
      }.to raise_error(Ai::ProviderClientService::ValidationError, /at least one message/)
    end
  end

  describe '#track_usage' do
    let(:service) { described_class.new(openai_credential) }

    it 'tracks successful request metrics' do
      response_data = {
        usage: { total_tokens: 150, prompt_tokens: 50, completion_tokens: 100 },
        model: 'gpt-3.5-turbo'
      }

      expect {
        service.send(:track_usage, response_data, 1500, true)
      }.to change {
        service.instance_variable_get(:@usage_metrics)[:total_requests]
      }.by(1)
    end

    it 'tracks token usage correctly' do
      response_data = {
        usage: { total_tokens: 150, prompt_tokens: 50, completion_tokens: 100 }
      }

      service.send(:track_usage, response_data, 1500, true)
      metrics = service.instance_variable_get(:@usage_metrics)

      expect(metrics[:total_tokens]).to eq(150)
      expect(metrics[:prompt_tokens]).to eq(50)
      expect(metrics[:completion_tokens]).to eq(100)
    end

    it 'tracks response times' do
      service.send(:track_usage, {}, 2500, true)
      metrics = service.instance_variable_get(:@usage_metrics)

      expect(metrics[:total_response_time]).to eq(2500)
      expect(metrics[:avg_response_time]).to eq(2500.0)
    end

    it 'tracks failure rates' do
      service.send(:track_usage, {}, 1000, false)
      metrics = service.instance_variable_get(:@usage_metrics)

      expect(metrics[:failed_requests]).to eq(1)
      expect(metrics[:success_rate]).to eq(0.0)
    end
  end

  describe '#circuit_breaker' do
    let(:service) { described_class.new(openai_credential) }

    before do
      stub_request(:post, 'https://api.openai.com/v1/chat/completions')
        .to_return(status: 500, body: '{"error": "Server error"}')

      # Simulate multiple failures to trigger circuit breaker
      5.times do
        service.send_message([ { role: 'user', content: 'test' } ], { model: 'gpt-3.5-turbo' })
      end
    end

    it 'opens circuit after multiple failures' do
      # Circuit breaker is open when @circuit_breaker_opened_at is set
      expect(service.instance_variable_get(:@circuit_breaker_opened_at)).to be_present
    end

    it 'blocks requests when circuit is open' do
      result = service.send_message([ { role: 'user', content: 'test' } ], { model: 'gpt-3.5-turbo' })

      expect(result[:success]).to be false
      expect(result[:error]).to include('Circuit breaker is open')
      expect(result[:error_type]).to eq('circuit_breaker_open')
    end

    it 'includes retry information when circuit is open' do
      result = service.send_message([ { role: 'user', content: 'test' } ], { model: 'gpt-3.5-turbo' })

      expect(result[:retry_after]).to be > 0
      expect(result[:circuit_breaker_state]).to eq('open')
    end
  end

  describe '#rate_limit_handling' do
    let(:service) { described_class.new(openai_credential) }

    it 'respects rate limits' do
      # Simulate rate limit response
      stub_request(:post, 'https://api.openai.com/v1/chat/completions')
        .to_return(
          status: 429,
          headers: { 'Retry-After' => '60' },
          body: '{"error": {"code": "rate_limit_exceeded"}}'
        )

      result = service.send_message([ { role: 'user', content: 'test' } ], { model: 'gpt-3.5-turbo' })

      expect(result[:success]).to be false
      expect(result[:retry_after]).to eq(60)
    end

    it 'implements exponential backoff for retries' do
      service.instance_variable_set(:@consecutive_failures, 3)

      backoff_time = service.send(:calculate_backoff_time)
      expect(backoff_time).to be >= 8 # 2^3 seconds
    end
  end

  describe '#cost_estimation' do
    let(:provider_with_pricing) do
      create(:ai_provider, :openai, supported_models: [
        { "name" => "GPT-3.5 Turbo", "id" => "gpt-3.5-turbo", "context_length" => 16385,
          "cost_per_1k_tokens" => { "input" => 0.0005, "output" => 0.0015 } },
        { "name" => "GPT-4", "id" => "gpt-4", "context_length" => 8192,
          "cost_per_1k_tokens" => { "input" => 0.03, "output" => 0.06 } }
      ])
    end
    let(:credential_with_pricing) { create(:ai_provider_credential, account: account, provider: provider_with_pricing) }
    let(:service) { described_class.new(credential_with_pricing) }

    it 'estimates request costs accurately' do
      tokens_used = { prompt_tokens: 100, completion_tokens: 50 }
      model = 'gpt-3.5-turbo'

      cost = service.send(:estimate_cost, tokens_used, model)

      expect(cost).to be > 0
      expect(cost).to be_a(BigDecimal)
    end

    it 'handles different model pricing' do
      gpt_35_cost = service.send(:estimate_cost, { prompt_tokens: 100, completion_tokens: 50 }, 'gpt-3.5-turbo')
      gpt_4_cost = service.send(:estimate_cost, { prompt_tokens: 100, completion_tokens: 50 }, 'gpt-4')

      expect(gpt_4_cost).to be > gpt_35_cost
    end

    it 'falls back to default pricing when model not found' do
      cost = service.send(:estimate_cost, { prompt_tokens: 100, completion_tokens: 50 }, 'unknown-model')

      expect(cost).to be > 0
      expect(cost).to be_a(BigDecimal)
    end
  end

  describe '#health_check' do
    it 'performs health check for provider' do
      stub_successful_openai_response

      service = described_class.new(openai_credential)
      health = service.health_check

      expect(health).to include(
        :healthy,
        :response_time_ms,
        :last_checked_at,
        :error_rate,
        :circuit_breaker_state
      )
      expect(health[:healthy]).to be true
    end

    it 'reports unhealthy when provider is down' do
      stub_request(:post, 'https://api.openai.com/v1/chat/completions')
        .to_timeout

      service = described_class.new(openai_credential)
      health = service.health_check

      expect(health[:healthy]).to be false
      expect(health[:last_error]).to be_present
    end
  end

  # Test helper methods
  private

  def stub_successful_openai_response
    stub_request(:post, 'https://api.openai.com/v1/chat/completions')
      .to_return(
        status: 200,
        body: {
          choices: [
            {
              message: {
                role: 'assistant',
                content: 'Hello! How can I help you today?'
              },
              finish_reason: 'stop'
            }
          ],
          usage: {
            prompt_tokens: 12,
            completion_tokens: 8,
            total_tokens: 20
          },
          model: 'gpt-3.5-turbo'
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  def stub_successful_anthropic_response
    stub_request(:post, 'https://api.anthropic.com/v1/messages')
      .to_return(
        status: 200,
        body: {
          content: [
            {
              type: 'text',
              text: 'Hello! How can I help you today?'
            }
          ],
          model: 'claude-3-sonnet-20240229',
          role: 'assistant',
          usage: {
            input_tokens: 12,
            output_tokens: 8
          }
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  def stub_successful_ollama_response
    stub_request(:post, 'http://localhost:11434/api/chat')
      .to_return(
        status: 200,
        body: {
          message: {
            role: 'assistant',
            content: 'Hello! How can I help you today?'
          },
          model: 'llama2'
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end
end

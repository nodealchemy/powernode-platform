# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiProviderTestService, type: :service do
  let(:account) { create(:account) }
  let(:openai_provider) { create(:ai_provider, :openai) }
  let(:anthropic_provider) { create(:ai_provider, :anthropic) }
  let(:ollama_provider) { create(:ai_provider, :ollama) }
  
  let(:openai_credential) do
    create(:ai_provider_credential,
           account: account,
           ai_provider: openai_provider,
           credentials: {
             api_key: 'sk-1234567890abcdef1234567890abcdef',
             model: 'gpt-3.5-turbo'
           }.to_json)
  end

  let(:anthropic_credential) do
    create(:ai_provider_credential,
           account: account,
           ai_provider: anthropic_provider,
           credentials: {
             api_key: 'sk-ant-api03-1234567890abcdef',
             model: 'claude-3-sonnet-20240229'
           }.to_json)
  end

  let(:ollama_credential) do
    create(:ai_provider_credential,
           account: account,
           ai_provider: ollama_provider,
           credentials: {
             base_url: 'http://localhost:11434',
             model: 'llama2'
           }.to_json)
  end

  describe '#initialize' do
    it 'initializes with credential' do
      service = described_class.new(openai_credential)
      expect(service.credential).to eq(openai_credential)
      expect(service.provider).to eq(openai_provider)
    end

    it 'sets up test configuration' do
      service = described_class.new(openai_credential)
      expect(service.instance_variable_get(:@test_config)).to be_a(Hash)
    end

    it 'initializes result tracking' do
      service = described_class.new(openai_credential)
      expect(service.instance_variable_get(:@test_results)).to be_a(Hash)
    end
  end

  describe '#test_connection' do
    context 'OpenAI provider tests' do
      let(:service) { described_class.new(openai_credential) }

      before do
        stub_successful_openai_connection
      end

      it 'successfully tests OpenAI connection' do
        result = service.test_connection
        
        expect(result[:success]).to be true
        expect(result[:response_time_ms]).to be > 0
        expect(result[:provider_type]).to eq('openai')
        expect(result[:test_timestamp]).to be_within(1.second).of(Time.current)
      end

      it 'returns detailed connection metrics' do
        result = service.test_connection
        
        expect(result).to include(
          :success,
          :response_time_ms,
          :status_code,
          :provider_response,
          :error_details,
          :connection_quality,
          :test_message_sent,
          :test_message_received
        )
      end

      it 'measures response time accurately' do
        # Simulate delayed response
        stub_delayed_openai_response(delay: 1.5)
        
        result = service.test_connection
        
        expect(result[:response_time_ms]).to be > 1400
        expect(result[:response_time_ms]).to be < 2000
      end

      it 'tests with minimal test message' do
        result = service.test_connection
        
        expect(result[:test_message_sent]).to include('Hello')
        expect(result[:test_message_received]).to be_present
        expect(result[:test_message_received].length).to be > 5
      end
    end

    context 'Anthropic provider tests' do
      let(:service) { described_class.new(anthropic_credential) }

      before do
        stub_successful_anthropic_connection
      end

      it 'successfully tests Anthropic connection' do
        result = service.test_connection
        
        expect(result[:success]).to be true
        expect(result[:provider_type]).to eq('anthropic')
        expect(result[:response_time_ms]).to be > 0
      end

      it 'handles Anthropic-specific response format' do
        result = service.test_connection
        
        expect(result[:provider_response]).to include('content')
        expect(result[:test_message_received]).to include('Hello')
      end
    end

    context 'Ollama provider tests' do
      let(:service) { described_class.new(ollama_credential) }

      before do
        stub_successful_ollama_connection
      end

      it 'successfully tests Ollama connection' do
        result = service.test_connection
        
        expect(result[:success]).to be true
        expect(result[:provider_type]).to eq('ollama')
        expect(result[:connection_type]).to eq('local')
      end

      it 'tests custom Ollama base URL' do
        custom_credential = create(:ai_provider_credential,
                                 account: account,
                                 ai_provider: ollama_provider,
                                 credentials: {
                                   base_url: 'http://custom-host:11434',
                                   model: 'llama2'
                                 }.to_json)
        
        service = described_class.new(custom_credential)
        
        stub_request(:post, 'http://custom-host:11434/api/chat')
          .to_return(
            status: 200,
            body: { message: { role: 'assistant', content: 'Hello!' } }.to_json
          )
        
        result = service.test_connection
        expect(result[:success]).to be true
      end
    end

    context 'connection failures' do
      let(:service) { described_class.new(openai_credential) }

      it 'handles authentication failures' do
        stub_request(:post, 'https://api.openai.com/v1/chat/completions')
          .to_return(status: 401, body: '{"error": {"code": "invalid_api_key"}}')

        result = service.test_connection
        
        expect(result[:success]).to be false
        expect(result[:error_type]).to eq('authentication_error')
        expect(result[:error_details]).to include('invalid_api_key')
      end

      it 'handles network timeouts' do
        stub_request(:post, 'https://api.openai.com/v1/chat/completions')
          .to_timeout

        result = service.test_connection
        
        expect(result[:success]).to be false
        expect(result[:error_type]).to eq('network_timeout')
        expect(result[:response_time_ms]).to be_nil
      end

      it 'handles rate limiting' do
        stub_request(:post, 'https://api.openai.com/v1/chat/completions')
          .to_return(
            status: 429,
            headers: { 'Retry-After' => '60' },
            body: '{"error": {"code": "rate_limit_exceeded"}}'
          )

        result = service.test_connection
        
        expect(result[:success]).to be false
        expect(result[:error_type]).to eq('rate_limit_exceeded')
        expect(result[:retry_after_seconds]).to eq(60)
      end

      it 'handles server errors' do
        stub_request(:post, 'https://api.openai.com/v1/chat/completions')
          .to_return(status: 500, body: 'Internal Server Error')

        result = service.test_connection
        
        expect(result[:success]).to be false
        expect(result[:error_type]).to eq('server_error')
        expect(result[:status_code]).to eq(500)
      end

      it 'handles malformed responses' do
        stub_request(:post, 'https://api.openai.com/v1/chat/completions')
          .to_return(status: 200, body: 'invalid json response')

        result = service.test_connection
        
        expect(result[:success]).to be false
        expect(result[:error_type]).to eq('invalid_response')
      end
    end
  end

  describe '#test_with_details' do
    let(:service) { described_class.new(openai_credential) }

    before do
      stub_successful_openai_connection
    end

    it 'performs comprehensive testing with detailed metrics' do
      result = service.test_with_details
      
      expect(result).to include(
        :connection_test,
        :performance_metrics,
        :capability_tests,
        :error_handling_tests,
        :overall_health_score,
        :recommendations
      )
    end

    it 'includes performance benchmarks' do
      result = service.test_with_details
      
      performance = result[:performance_metrics]
      expect(performance).to include(
        :average_response_time,
        :throughput_score,
        :reliability_score,
        :latency_percentiles
      )
    end

    it 'tests various capabilities' do
      result = service.test_with_details
      
      capabilities = result[:capability_tests]
      expect(capabilities).to include(
        :text_generation,
        :model_availability,
        :parameter_support,
        :streaming_support
      )
    end

    it 'tests error handling scenarios' do
      result = service.test_with_details
      
      error_tests = result[:error_handling_tests]
      expect(error_tests).to include(
        :invalid_request_handling,
        :rate_limit_behavior,
        :timeout_handling
      )
    end

    it 'calculates overall health score' do
      result = service.test_with_details
      
      health_score = result[:overall_health_score]
      expect(health_score).to be >= 0
      expect(health_score).to be <= 1
    end

    it 'provides actionable recommendations' do
      result = service.test_with_details
      
      recommendations = result[:recommendations]
      expect(recommendations).to be_an(Array)
      
      if recommendations.any?
        rec = recommendations.first
        expect(rec).to include(:type, :description, :priority)
      end
    end
  end

  describe '#continuous_health_check' do
    let(:service) { described_class.new(openai_credential) }

    before do
      stub_successful_openai_connection
    end

    it 'performs continuous monitoring' do
      expect {
        service.start_continuous_health_check(interval: 0.1, duration: 0.5)
      }.to change { 
        service.instance_variable_get(:@health_check_results)&.size || 0 
      }.by_at_least(3)
    end

    it 'tracks health metrics over time' do
      service.start_continuous_health_check(interval: 0.1, duration: 0.3)
      
      results = service.get_health_check_history
      expect(results.size).to be >= 2
      
      first_result = results.first
      expect(first_result).to include(
        :timestamp,
        :success,
        :response_time_ms,
        :health_score
      )
    end

    it 'detects performance degradation' do
      # First, establish baseline with good performance
      stub_successful_openai_connection
      service.start_continuous_health_check(interval: 0.1, duration: 0.2)
      
      # Then simulate degraded performance
      stub_delayed_openai_response(delay: 3.0)
      service.start_continuous_health_check(interval: 0.1, duration: 0.2)
      
      degradation = service.detect_performance_degradation
      expect(degradation[:degradation_detected]).to be true
    end

    it 'provides health trend analysis' do
      service.start_continuous_health_check(interval: 0.1, duration: 0.5)
      
      trends = service.analyze_health_trends
      expect(trends).to include(
        :trend_direction,
        :average_response_time,
        :success_rate_trend,
        :stability_score
      )
    end
  end

  describe '#load_test' do
    let(:service) { described_class.new(openai_credential) }

    before do
      stub_successful_openai_connection
    end

    it 'performs concurrent load testing' do
      load_test_result = service.load_test(
        concurrent_requests: 5,
        duration_seconds: 2,
        ramp_up_time: 0.5
      )
      
      expect(load_test_result).to include(
        :total_requests,
        :successful_requests,
        :failed_requests,
        :average_response_time,
        :requests_per_second,
        :error_rate,
        :throughput_score
      )
    end

    it 'measures throughput under load' do
      result = service.load_test(concurrent_requests: 3, duration_seconds: 1)
      
      expect(result[:total_requests]).to be >= 3
      expect(result[:requests_per_second]).to be > 0
      expect(result[:throughput_score]).to be >= 0
    end

    it 'identifies rate limiting thresholds' do
      # Simulate rate limiting after several requests
      request_count = 0
      stub_request(:post, 'https://api.openai.com/v1/chat/completions')
        .to_return do |request|
          request_count += 1
          if request_count > 3
            { status: 429, body: '{"error": {"code": "rate_limit_exceeded"}}' }
          else
            { 
              status: 200, 
              body: {
                choices: [{ message: { role: 'assistant', content: 'Hello!' } }],
                usage: { total_tokens: 10 }
              }.to_json
            }
          end
        end

      result = service.load_test(concurrent_requests: 5, duration_seconds: 1)
      
      expect(result[:rate_limit_encountered]).to be true
      expect(result[:rate_limit_threshold]).to be_present
    end
  end

  describe '#test_model_availability' do
    let(:service) { described_class.new(openai_credential) }

    it 'tests availability of specified models' do
      models_to_test = ['gpt-3.5-turbo', 'gpt-4', 'gpt-4-turbo']
      
      models_to_test.each do |model|
        stub_request(:post, 'https://api.openai.com/v1/chat/completions')
          .with(body: hash_including(model: model))
          .to_return(
            status: 200,
            body: {
              choices: [{ message: { role: 'assistant', content: 'Test response' } }],
              model: model,
              usage: { total_tokens: 15 }
            }.to_json
          )
      end

      availability_results = service.test_model_availability(models_to_test)
      
      expect(availability_results).to be_a(Hash)
      models_to_test.each do |model|
        expect(availability_results[model]).to include(
          :available,
          :response_time_ms,
          :test_successful
        )
      end
    end

    it 'handles model unavailability' do
      unavailable_model = 'gpt-5-nonexistent'
      
      stub_request(:post, 'https://api.openai.com/v1/chat/completions')
        .with(body: hash_including(model: unavailable_model))
        .to_return(
          status: 404,
          body: '{"error": {"code": "model_not_found", "message": "Model not found"}}'
        )

      result = service.test_model_availability([unavailable_model])
      
      expect(result[unavailable_model][:available]).to be false
      expect(result[unavailable_model][:error]).to include('model_not_found')
    end
  end

  describe '#benchmark_performance' do
    let(:service) { described_class.new(openai_credential) }

    before do
      stub_successful_openai_connection
    end

    it 'benchmarks various performance aspects' do
      benchmark_result = service.benchmark_performance
      
      expect(benchmark_result).to include(
        :latency_benchmark,
        :throughput_benchmark,
        :quality_benchmark,
        :cost_benchmark,
        :overall_score
      )
    end

    it 'measures latency across different request sizes' do
      benchmark = service.benchmark_performance
      
      latency = benchmark[:latency_benchmark]
      expect(latency).to include(
        :small_request_latency,
        :medium_request_latency,
        :large_request_latency,
        :latency_consistency_score
      )
    end

    it 'evaluates response quality metrics' do
      benchmark = service.benchmark_performance
      
      quality = benchmark[:quality_benchmark]
      expect(quality).to include(
        :response_relevance,
        :response_completeness,
        :consistency_score
      )
    end

    it 'calculates cost efficiency scores' do
      benchmark = service.benchmark_performance
      
      cost = benchmark[:cost_benchmark]
      expect(cost).to include(
        :cost_per_token,
        :cost_per_request,
        :cost_efficiency_score
      )
    end
  end

  describe '#generate_test_report' do
    let(:service) { described_class.new(openai_credential) }

    before do
      stub_successful_openai_connection
      # Run some tests to generate data
      service.test_connection
      service.test_with_details
    end

    it 'generates comprehensive test report' do
      report = service.generate_test_report
      
      expect(report).to include(
        :summary,
        :test_results,
        :performance_analysis,
        :recommendations,
        :detailed_metrics,
        :timestamp
      )
    end

    it 'includes executive summary' do
      report = service.generate_test_report
      
      summary = report[:summary]
      expect(summary).to include(
        :overall_status,
        :health_score,
        :key_findings,
        :critical_issues
      )
    end

    it 'provides detailed performance analysis' do
      report = service.generate_test_report
      
      analysis = report[:performance_analysis]
      expect(analysis).to include(
        :response_time_analysis,
        :reliability_analysis,
        :capability_analysis,
        :comparison_with_benchmarks
      )
    end

    it 'includes actionable recommendations' do
      report = service.generate_test_report
      
      recommendations = report[:recommendations]
      expect(recommendations).to be_an(Array)
      
      if recommendations.any?
        rec = recommendations.first
        expect(rec).to include(
          :priority,
          :category,
          :description,
          :implementation_steps
        )
      end
    end
  end

  describe 'class methods' do
    describe '.test_all_credentials' do
      before do
        openai_credential
        anthropic_credential
        ollama_credential
        
        stub_successful_openai_connection
        stub_successful_anthropic_connection
        stub_successful_ollama_connection
      end

      it 'tests all credentials for an account' do
        results = described_class.test_all_credentials(account)
        
        expect(results).to be_an(Array)
        expect(results.size).to eq(3)
        
        results.each do |result|
          expect(result).to include(
            :credential_id,
            :provider_name,
            :success,
            :response_time_ms
          )
        end
      end

      it 'provides summary statistics' do
        results = described_class.test_all_credentials(account)
        summary = described_class.summarize_test_results(results)
        
        expect(summary).to include(
          :total_credentials,
          :successful_tests,
          :failed_tests,
          :average_response_time,
          :fastest_provider,
          :slowest_provider
        )
      end
    end

    describe '.health_check_all_providers' do
      it 'performs health checks across all active providers' do
        create_list(:ai_provider, 3, :active)
        
        health_results = described_class.health_check_all_providers
        
        expect(health_results).to be_an(Array)
        expect(health_results.size).to eq(3)
      end
    end
  end

  # Test helper methods
  private

  def stub_successful_openai_connection
    stub_request(:post, 'https://api.openai.com/v1/chat/completions')
      .to_return(
        status: 200,
        body: {
          choices: [
            {
              message: {
                role: 'assistant',
                content: 'Hello! This is a test response.'
              }
            }
          ],
          usage: { total_tokens: 20, prompt_tokens: 8, completion_tokens: 12 },
          model: 'gpt-3.5-turbo'
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  def stub_successful_anthropic_connection
    stub_request(:post, 'https://api.anthropic.com/v1/messages')
      .to_return(
        status: 200,
        body: {
          content: [
            {
              type: 'text',
              text: 'Hello! This is a test response.'
            }
          ],
          model: 'claude-3-sonnet-20240229',
          role: 'assistant',
          usage: { input_tokens: 8, output_tokens: 12 }
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  def stub_successful_ollama_connection
    stub_request(:post, 'http://localhost:11434/api/chat')
      .to_return(
        status: 200,
        body: {
          message: {
            role: 'assistant',
            content: 'Hello! This is a test response.'
          },
          model: 'llama2'
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  def stub_delayed_openai_response(delay:)
    stub_request(:post, 'https://api.openai.com/v1/chat/completions')
      .to_return do |request|
        sleep(delay)
        {
          status: 200,
          body: {
            choices: [{ message: { role: 'assistant', content: 'Delayed response' } }],
            usage: { total_tokens: 15 }
          }.to_json
        }
      end
  end
end
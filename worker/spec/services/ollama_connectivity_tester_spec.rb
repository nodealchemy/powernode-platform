# frozen_string_literal: true

require 'rails_helper'
require_relative '../../app/services/ollama_connectivity_tester'

RSpec.describe OllamaConnectivityTester do
  let(:http) { instance_double(OllamaConnectivityTestJob) }
  let(:base_url) { 'http://localhost:11434' }

  # Minimal stand-in for a Net::HTTPResponse (the shape make_http_request returns).
  def response(code, body = '')
    double('response', code: code, body: body)
  end

  def build(config = {})
    described_class.new(test_config: config, http_requester: http)
  end

  describe '#calculate_tokens_per_second' do
    subject(:tester) { build }

    it 'computes tokens/sec from eval_count and eval_duration (nanoseconds)' do
      # 10 tokens over 2s (2e9 ns) => 5 tok/s
      result = tester.calculate_tokens_per_second('eval_count' => 10, 'eval_duration' => 2_000_000_000)
      expect(result).to eq(5.0)
    end

    it 'returns 0 when eval data is missing' do
      expect(tester.calculate_tokens_per_second({})).to eq(0)
    end

    it 'returns 0 when eval_duration is zero' do
      expect(tester.calculate_tokens_per_second('eval_count' => 10, 'eval_duration' => 0)).to eq(0)
    end
  end

  describe '#determine_overall_status' do
    subject(:tester) { build }

    def with_tests(statuses)
      tests = statuses.each_with_index.to_h { |s, i| ["test_#{i}", { status: s }] }
      tester.instance_variable_set(:@results, { tests: tests })
    end

    it "returns 'passed' when every test passed" do
      with_tests(%w[passed passed])
      expect(tester.determine_overall_status).to eq('passed')
    end

    it "returns 'failed' when any test failed (failed wins over warning)" do
      with_tests(%w[passed warning failed])
      expect(tester.determine_overall_status).to eq('failed')
    end

    it "returns 'warning' when any test warns and none failed" do
      with_tests(%w[passed warning])
      expect(tester.determine_overall_status).to eq('warning')
    end

    it "returns 'unknown' for any other mix of statuses" do
      with_tests(%w[running running])
      expect(tester.determine_overall_status).to eq('unknown')
    end
  end

  describe '#test_basic_connection' do
    it 'passes and captures the version on a 200' do
      allow(http).to receive(:make_http_request).and_return(response(200, { version: '0.1.27' }.to_json))

      result = build.test_basic_connection

      expect(result[:status]).to eq('passed')
      expect(result[:response_code]).to eq(200)
      expect(result[:version]).to eq('0.1.27')
    end

    it 'fails on a non-200 response' do
      allow(http).to receive(:make_http_request).and_return(response(500, 'boom'))

      result = build.test_basic_connection

      expect(result[:status]).to eq('failed')
      expect(result[:error]).to include('HTTP 500')
    end

    it 'fails when the HTTP call raises' do
      allow(http).to receive(:make_http_request).and_raise(StandardError.new('refused'))

      result = build.test_basic_connection

      expect(result[:status]).to eq('failed')
      expect(result[:error]).to include('Connection failed: refused')
    end
  end

  describe '#test_authentication' do
    it 'passes on 200 and records whether auth was supplied' do
      allow(http).to receive(:make_http_request).and_return(response(200, '{}'))

      result = build(auth_token: 'secret').test_authentication

      expect(result[:status]).to eq('passed')
      expect(result[:authentication_required]).to be(true)
      expect(result[:response_code]).to eq(200)
    end

    it 'reports an authentication failure on 401' do
      allow(http).to receive(:make_http_request).and_return(response(401, 'unauthorized'))

      result = build.test_authentication

      expect(result[:status]).to eq('failed')
      expect(result[:error]).to eq('Authentication failed - invalid or missing credentials')
      expect(result[:response_code]).to eq(401)
    end
  end

  describe '#test_model_listing' do
    it 'passes and lists available models on 200' do
      body = { models: [{ name: 'llama2' }, { name: 'mistral' }] }.to_json
      allow(http).to receive(:make_http_request).and_return(response(200, body))

      result = build.test_model_listing

      expect(result[:status]).to eq('passed')
      expect(result[:model_count]).to eq(2)
      expect(result[:available_models]).to eq(%w[llama2 mistral])
    end

    it 'fails on a non-200 response' do
      allow(http).to receive(:make_http_request).and_return(response(503, 'down'))

      result = build.test_model_listing

      expect(result[:status]).to eq('failed')
      expect(result[:error]).to include('HTTP 503')
    end
  end

  describe '#test_model_availability' do
    it 'passes and extracts model details on 200' do
      body = { details: { family: 'llama', parameter_size: '7B', quantization_level: 'Q4_0' } }.to_json
      allow(http).to receive(:make_http_request).and_return(response(200, body))

      result = build(test_model: 'llama2').test_model_availability

      expect(result[:status]).to eq('passed')
      expect(result[:model_name]).to eq('llama2')
      expect(result[:model_info]).to eq(family: 'llama', parameter_size: '7B', quantization_level: 'Q4_0')
    end

    it 'fails with a not-found message on 404' do
      allow(http).to receive(:make_http_request).and_return(response(404, 'nope'))

      result = build(test_model: 'ghost').test_model_availability

      expect(result[:status]).to eq('failed')
      expect(result[:error]).to eq("Model 'ghost' not found on server")
      expect(result[:response_code]).to eq(404)
    end
  end

  describe '#test_basic_inference' do
    it 'passes when the model returns content and reports tokens/sec' do
      body = {
        message: { content: 'Hello there!' },
        eval_count: 10,
        eval_duration: 2_000_000_000
      }.to_json
      allow(http).to receive(:make_http_request).and_return(response(200, body))

      result = build(test_model: 'llama2').test_basic_inference

      expect(result[:status]).to eq('passed')
      expect(result[:response]).to eq('Hello there!')
      expect(result[:tokens_per_second]).to eq(5.0)
      expect(result[:eval_count]).to eq(10)
    end

    it 'fails when the response content is blank' do
      allow(http).to receive(:make_http_request).and_return(response(200, { message: { content: '' } }.to_json))

      result = build.test_basic_inference

      expect(result[:status]).to eq('failed')
    end

    it 'fails on a non-200 response' do
      allow(http).to receive(:make_http_request).and_return(response(500, 'err'))

      result = build.test_basic_inference

      expect(result[:status]).to eq('failed')
      expect(result[:error]).to include('HTTP 500')
    end
  end

  describe '#test_streaming_capability' do
    it 'passes when multiple chunks stream back' do
      streamed = "{\"x\":1}\n{\"x\":2}\n{\"x\":3}\n"
      allow(http).to receive(:make_http_request).and_return(response(200, streamed))

      result = build.test_streaming_capability

      expect(result[:status]).to eq('passed')
      expect(result[:chunks_received]).to eq(3)
      expect(result[:streaming_supported]).to be(true)
    end

    it 'fails when only a single chunk is returned' do
      allow(http).to receive(:make_http_request).and_return(response(200, "{\"x\":1}\n"))

      result = build.test_streaming_capability

      expect(result[:status]).to eq('failed')
      expect(result[:streaming_supported]).to be(false)
    end
  end

  describe '#test_performance_metrics' do
    it 'aggregates response time and token-rate metrics across 3 runs' do
      body = { eval_count: 10, eval_duration: 2_000_000_000 }.to_json
      allow(http).to receive(:make_http_request).and_return(response(200, body))

      tester = build(test_model: 'llama2')
      allow(tester).to receive(:sleep) # skip the inter-run pause

      result = tester.test_performance_metrics

      expect(result[:status]).to eq('passed')
      expect(result[:test_count]).to eq(3)
      expect(result[:avg_tokens_per_second]).to eq(5.0)
      expect(result).to have_key(:avg_response_time_ms)
    end
  end

  describe '#run' do
    # Route each endpoint to a healthy canned response.
    def stub_all_ok
      allow(http).to receive(:make_http_request) do |url, **_opts|
        case url
        when %r{/api/version}
          response(200, { version: '0.1.27' }.to_json)
        when %r{/api/tags}
          response(200, { models: [{ name: 'llama2' }] }.to_json)
        when %r{/api/show}
          response(200, { details: { family: 'llama' } }.to_json)
        when %r{/api/chat}
          response(200, { message: { content: 'ok' }, eval_count: 10, eval_duration: 2_000_000_000 }.to_json)
        else
          response(200, '{}')
        end
      end
    end

    it 'runs the core suite and returns tests + overall status' do
      stub_all_ok
      tester = build(test_model: 'llama2')
      allow(tester).to receive(:sleep)

      outcome = tester.run

      expect(outcome[:overall_status]).to eq('passed')
      expect(outcome[:tests].keys).to contain_exactly(
        'basic_connection', 'authentication', 'model_listing',
        'model_availability', 'basic_inference', 'performance_metrics'
      )
    end

    it 'includes the streaming test only when test_streaming is requested' do
      stub_all_ok
      tester = build(test_model: 'llama2', test_streaming: true)
      allow(tester).to receive(:sleep)

      outcome = tester.run

      expect(outcome[:tests]).to have_key('streaming_capability')
    end
  end
end

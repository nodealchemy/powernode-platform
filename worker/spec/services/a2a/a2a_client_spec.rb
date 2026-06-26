# frozen_string_literal: true

require 'rails_helper'
require_relative '../../../app/services/a2a/a2a_client'

RSpec.describe A2a::A2aClient do
  # Stand-in for the job, which is the real http_requester in production.
  let(:http) { instance_double(AiA2aExternalTaskJob) }

  subject(:client) { described_class.new(http_requester: http) }

  # Minimal stand-in for a Net::HTTPResponse (the shape make_http_request returns).
  def response(code, body = '')
    double('response', code: code, body: body)
  end

  describe '#build_a2a_request' do
    it 'builds the A2A tasks/send envelope from the task' do
      task = {
        'task_id' => 'tk-1',
        'message' => { 'role' => 'user', 'parts' => [{ 'type' => 'text', 'text' => 'hi' }] },
        'session_id' => 'sess-9',
        'history' => [{ 'a' => 1 }, { 'b' => 2 }],
        'metadata' => { 'foo' => 'bar' }
      }

      request = client.build_a2a_request(task)

      expect(request[:id]).to eq('tk-1')
      expect(request[:message]).to eq('role' => 'user', 'parts' => [{ 'type' => 'text', 'text' => 'hi' }])
      expect(request[:sessionId]).to eq('sess-9')
      expect(request[:historyLength]).to eq(2)
      expect(request[:acceptedOutputModes]).to eq(['application/json', 'text/plain'])
      expect(request[:metadata]).to eq('foo' => 'bar')
    end

    it 'defaults message/history/metadata when absent' do
      request = client.build_a2a_request('task_id' => 'tk-2', 'session_id' => nil)

      expect(request[:message]).to eq({})
      expect(request[:historyLength]).to eq(0)
      expect(request[:metadata]).to eq({})
    end
  end

  describe '#build_a2a_headers' do
    let(:base_headers) do
      {
        'Content-Type' => 'application/json',
        'Accept' => 'application/json',
        'X-A2A-Version' => '0.3'
      }
    end

    it 'always sets the A2A content-type/accept/version headers' do
      expect(client.build_a2a_headers({})).to eq(base_headers)
    end

    it 'adds a bearer Authorization header' do
      headers = client.build_a2a_headers('type' => 'bearer', 'token' => 'abc123')

      expect(headers['Authorization']).to eq('Bearer abc123')
    end

    it 'adds an api_key header under the default X-API-Key name' do
      headers = client.build_a2a_headers('type' => 'api_key', 'key' => 'k-1')

      expect(headers['X-API-Key']).to eq('k-1')
    end

    it 'adds an api_key header under a custom header name' do
      headers = client.build_a2a_headers('type' => 'api_key', 'key' => 'k-2', 'header_name' => 'X-Custom-Key')

      expect(headers['X-Custom-Key']).to eq('k-2')
      expect(headers).not_to have_key('X-API-Key')
    end

    it 'adds a basic Authorization header from base64(user:pass)' do
      headers = client.build_a2a_headers('type' => 'basic', 'username' => 'u', 'password' => 'p')

      expect(headers['Authorization']).to eq("Basic #{Base64.strict_encode64('u:p')}")
    end

    it 'adds no auth header for an unknown/blank type' do
      expect(client.build_a2a_headers('type' => 'oauth')).to eq(base_headers)
    end
  end

  describe '#execute (dispatch)' do
    let(:task) do
      {
        'task_id' => 'tk-1',
        'external_endpoint_url' => 'https://agent.example.test/a2a',
        'external_authentication' => { 'type' => 'bearer', 'token' => 'tok' },
        'message' => { 'parts' => [{ 'type' => 'text', 'text' => 'hi' }] }
      }
    end

    it 'routes to the standard request by default' do
      allow(client).to receive(:execute_standard_request).and_return(success: true, output: 'std')

      expect(client.execute(task)).to eq(success: true, output: 'std')
      expect(client).to have_received(:execute_standard_request).with(
        'https://agent.example.test/a2a', a_hash_including('Authorization' => 'Bearer tok'), a_hash_including(id: 'tk-1'), kind_of(Time), 120
      )
    end

    it 'routes to the streaming request when metadata.streaming is true' do
      streaming_task = task.merge('metadata' => { 'streaming' => true })
      allow(client).to receive(:execute_streaming_request).and_return(success: true, output: 'stream')

      expect(client.execute(streaming_task)).to eq(success: true, output: 'stream')
      expect(client).to have_received(:execute_streaming_request)
    end

    it 'passes a metadata timeout override through to the standard request' do
      timed_task = task.merge('metadata' => { 'timeout' => 5 })
      allow(client).to receive(:execute_standard_request).and_return(success: true)

      client.execute(timed_task)

      expect(client).to have_received(:execute_standard_request).with(anything, anything, anything, kind_of(Time), 5)
    end
  end

  describe '#execute_standard_request' do
    let(:url) { 'https://agent.example.test/a2a' }
    let(:headers) { { 'Content-Type' => 'application/json' } }
    let(:body) { { id: 'tk-1' } }
    let(:start_time) { Time.current }

    it 'parses a 2xx body as an A2A response' do
      completed = { status: { state: 'completed' }, message: { parts: [{ type: 'text', text: 'done' }] } }.to_json
      allow(http).to receive(:make_http_request).and_return(response(200, completed))

      result = client.execute_standard_request(url, headers, body, start_time)

      expect(result[:success]).to be true
      expect(result[:output]['content']).to eq('done')
      expect(result).to have_key(:duration_ms)
    end

    it 'sends a POST with the JSON body and provided headers/timeout' do
      allow(http).to receive(:make_http_request).and_return(response(200, { status: { state: 'completed' } }.to_json))

      client.execute_standard_request(url, headers, body, start_time, 42)

      expect(http).to have_received(:make_http_request).with(
        url, method: :post, headers: headers, body: body.to_json, timeout: 42
      )
    end

    it 'parses a non-2xx body as an A2A error' do
      allow(http).to receive(:make_http_request).and_return(
        response(500, { error: { message: 'boom', code: 'SRV' } }.to_json)
      )

      result = client.execute_standard_request(url, headers, body, start_time)

      expect(result[:success]).to be false
      expect(result[:error]).to eq('boom')
      expect(result[:error_code]).to eq('SRV')
    end

    it 'maps read timeouts to a TIMEOUT error code' do
      allow(http).to receive(:make_http_request).and_raise(Net::ReadTimeout)

      result = client.execute_standard_request(url, headers, body, start_time)

      expect(result[:success]).to be false
      expect(result[:error_code]).to eq('TIMEOUT')
    end

    it 'maps other transport failures to a CONNECTION_ERROR code' do
      allow(http).to receive(:make_http_request).and_raise(StandardError.new('refused'))

      result = client.execute_standard_request(url, headers, body, start_time)

      expect(result[:success]).to be false
      expect(result[:error_code]).to eq('CONNECTION_ERROR')
      expect(result[:error]).to include('refused')
    end
  end

  describe '#parse_a2a_response' do
    it 'maps a completed state to a success result with extracted output' do
      body = {
        status: { state: 'completed' },
        message: { parts: [{ type: 'text', text: 'hello' }] },
        artifacts: [{ name: 'a' }]
      }.to_json

      result = client.parse_a2a_response(body, 12)

      expect(result[:success]).to be true
      expect(result[:output]['content']).to eq('hello')
      expect(result[:artifacts]).to eq([{ 'name' => 'a' }])
      expect(result[:duration_ms]).to eq(12)
    end

    it 'defaults to completed when no state is present' do
      result = client.parse_a2a_response({ message: {} }.to_json, 1)

      expect(result[:success]).to be true
    end

    it 'maps a failed state to an error result' do
      body = { status: { state: 'failed' }, error: { message: 'nope', code: 'X' } }.to_json

      result = client.parse_a2a_response(body, 5)

      expect(result[:success]).to be false
      expect(result[:error]).to eq('nope')
      expect(result[:error_code]).to eq('X')
    end

    it 'maps input-required to an input_required status with the prompt text' do
      body = {
        status: { state: 'input-required' },
        message: { parts: [{ type: 'text', text: 'need more' }] }
      }.to_json

      result = client.parse_a2a_response(body, 5)

      expect(result[:success]).to be true
      expect(result[:status]).to eq('input_required')
      expect(result[:output]['prompt']).to eq('need more')
    end

    it 'maps working/submitted to a poll-required active status' do
      %w[working submitted].each do |state|
        body = { id: 'ext-1', status: { state: state } }.to_json

        result = client.parse_a2a_response(body, 5)

        expect(result[:status]).to eq('active')
        expect(result[:poll_required]).to be true
        expect(result[:external_task_id]).to eq('ext-1')
      end
    end

    it 'maps an unknown state to an UNKNOWN_STATE error' do
      result = client.parse_a2a_response({ status: { state: 'weird' } }.to_json, 5)

      expect(result[:success]).to be false
      expect(result[:error_code]).to eq('UNKNOWN_STATE')
    end

    it 'maps malformed JSON to an INVALID_RESPONSE error' do
      result = client.parse_a2a_response('not json', 5)

      expect(result[:success]).to be false
      expect(result[:error_code]).to eq('INVALID_RESPONSE')
    end
  end

  describe '#parse_a2a_error' do
    it 'extracts message/code from a JSON error body' do
      result = client.parse_a2a_error({ error: { message: 'bad', code: 'E1' } }.to_json, 400, 3)

      expect(result).to eq(success: false, error: 'bad', error_code: 'E1', duration_ms: 3)
    end

    it 'falls back to the HTTP status when the body has no error fields' do
      result = client.parse_a2a_error({ something: 'else' }.to_json, 502, 3)

      expect(result[:error]).to eq('HTTP 502')
      expect(result[:error_code]).to eq('HTTP_502')
    end

    it 'truncates a non-JSON body into the error message' do
      result = client.parse_a2a_error('gateway timeout text', 504, 3)

      expect(result[:error]).to start_with('HTTP 504:')
      expect(result[:error_code]).to eq('HTTP_504')
    end
  end

  describe '#extract_text_from_message' do
    it 'joins the text parts with newlines' do
      message = { 'parts' => [
        { 'type' => 'text', 'text' => 'line one' },
        { 'type' => 'image', 'url' => 'x' },
        { 'type' => 'text', 'text' => 'line two' }
      ] }

      expect(client.extract_text_from_message(message)).to eq("line one\nline two")
    end

    it 'returns an empty string for a non-hash message' do
      expect(client.extract_text_from_message(nil)).to eq('')
      expect(client.extract_text_from_message('text')).to eq('')
    end
  end

  describe '#extract_output_from_response' do
    it 'wraps content, the raw message, and status' do
      data = {
        'message' => { 'parts' => [{ 'type' => 'text', 'text' => 'hi' }] },
        'status' => { 'state' => 'completed' }
      }

      output = client.extract_output_from_response(data)

      expect(output['content']).to eq('hi')
      expect(output['message']).to eq(data['message'])
      expect(output['status']).to eq('state' => 'completed')
    end
  end
end

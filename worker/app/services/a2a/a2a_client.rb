# frozen_string_literal: true

require 'json'
require 'base64'
require 'net/http'
require 'uri'
require 'timeout'

module A2a
  # Transport client for executing external A2A (Agent-to-Agent) protocol tasks.
  #
  # Owns the A2A protocol/transport work (request building, auth-scheme headers,
  # standard + streaming HTTP execution, response/error parsing, output/text
  # extraction) that was previously embedded in AiA2aExternalTaskJob. The job now
  # orchestrates (fetch task, kill-switch bail, flip status, complete/fail,
  # schedule polling) and delegates the protocol work here.
  #
  # Standard requests are delegated to an injected `http_requester` that responds to
  #   make_http_request(url, method:, headers:, body:, timeout:)
  # In production this is the job itself (via AiJobsConcern), which carries the
  # circuit-breaker wrapper and structured external-API logging — so the transport
  # behaviour is preserved unchanged. Streaming uses Net::HTTP directly (matching
  # the original job, which streamed outside the circuit breaker).
  #
  # All public execute_* methods return a uniform result hash consumed by the job:
  #   { success: true, output:, artifacts:, duration_ms:, ... }
  #   { success: false, error:, error_code:, duration_ms: }
  class A2aClient
    # A2A Protocol constants
    A2A_CONTENT_TYPE = 'application/json'
    A2A_VERSION = '0.3'
    DEFAULT_TIMEOUT = 120

    def initialize(http_requester:)
      @http = http_requester
    end

    # Build the A2A request/headers from the task, decide streaming, and dispatch.
    # Returns the uniform result hash the job consumes.
    def execute(task)
      start_time = Time.current

      endpoint_url = task['external_endpoint_url']
      authentication = task['external_authentication'] || {}

      request_body = build_a2a_request(task)
      headers = build_a2a_headers(authentication)
      timeout = task.dig('metadata', 'timeout') || DEFAULT_TIMEOUT

      use_streaming = task.dig('metadata', 'streaming') == true

      if use_streaming
        execute_streaming_request(endpoint_url, headers, request_body, start_time, timeout)
      else
        execute_standard_request(endpoint_url, headers, request_body, start_time, timeout)
      end
    end

    def build_a2a_request(task)
      message = task['message'] || {}

      # A2A tasks/send request format
      {
        id: task['task_id'],
        message: message,
        sessionId: task['session_id'],
        historyLength: (task['history'] || []).size,
        acceptedOutputModes: ['application/json', 'text/plain'],
        metadata: task['metadata'] || {}
      }
    end

    def build_a2a_headers(authentication)
      headers = {
        'Content-Type' => A2A_CONTENT_TYPE,
        'Accept' => A2A_CONTENT_TYPE,
        'X-A2A-Version' => A2A_VERSION
      }

      # Add authentication
      case authentication['type']
      when 'bearer'
        headers['Authorization'] = "Bearer #{authentication['token']}"
      when 'api_key'
        header_name = authentication['header_name'] || 'X-API-Key'
        headers[header_name] = authentication['key']
      when 'basic'
        credentials = Base64.strict_encode64("#{authentication['username']}:#{authentication['password']}")
        headers['Authorization'] = "Basic #{credentials}"
      end

      headers
    end

    def execute_standard_request(endpoint_url, headers, request_body, start_time, timeout = DEFAULT_TIMEOUT)
      begin
        response = @http.make_http_request(
          endpoint_url,
          method: :post,
          headers: headers,
          body: request_body.to_json,
          timeout: timeout
        )

        duration_ms = ((Time.current - start_time) * 1000).to_i

        if response.code.to_i >= 200 && response.code.to_i < 300
          parse_a2a_response(response.body, duration_ms)
        else
          parse_a2a_error(response.body, response.code, duration_ms)
        end

      rescue Net::ReadTimeout, Net::OpenTimeout, Timeout::Error => e
        {
          success: false,
          error: "External A2A endpoint timeout: #{e.message}",
          error_code: 'TIMEOUT',
          duration_ms: ((Time.current - start_time) * 1000).to_i
        }
      rescue StandardError => e
        {
          success: false,
          error: "External A2A connection failed: #{e.message}",
          error_code: 'CONNECTION_ERROR',
          duration_ms: ((Time.current - start_time) * 1000).to_i
        }
      end
    end

    def execute_streaming_request(endpoint_url, headers, request_body, start_time, timeout = DEFAULT_TIMEOUT)
      begin
        uri = URI(endpoint_url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.read_timeout = timeout
        http.open_timeout = 30

        request = Net::HTTP::Post.new(uri)
        headers.each { |k, v| request[k] = v }
        request['Accept'] = 'text/event-stream'
        request.body = request_body.to_json

        accumulated_content = ""
        final_data = nil

        http.request(request) do |response|
          if response.code.to_i >= 200 && response.code.to_i < 300
            response.read_body do |chunk|
              chunk.split("\n").each do |line|
                next if line.strip.empty?
                next unless line.start_with?('data: ')

                json_str = line.sub('data: ', '')
                next if json_str == '[DONE]'

                begin
                  event_data = JSON.parse(json_str)
                  if event_data['status']&.dig('state') == 'completed'
                    final_data = event_data
                  elsif event_data.dig('message', 'parts')
                    text = event_data['message']['parts']
                      .select { |p| p['type'] == 'text' }
                      .map { |p| p['text'] }
                      .join
                    accumulated_content += text
                  end
                rescue JSON::ParserError
                  next
                end
              end
            end
          else
            return parse_a2a_error(response.body, response.code, ((Time.current - start_time) * 1000).to_i)
          end
        end

        duration_ms = ((Time.current - start_time) * 1000).to_i

        if final_data
          parse_a2a_response(final_data.to_json, duration_ms)
        else
          {
            success: true,
            output: { 'content' => accumulated_content },
            duration_ms: duration_ms
          }
        end

      rescue Net::ReadTimeout, Net::OpenTimeout, Timeout::Error => e
        {
          success: false,
          error: "Streaming timeout: #{e.message}",
          error_code: 'TIMEOUT',
          duration_ms: ((Time.current - start_time) * 1000).to_i
        }
      rescue StandardError => e
        {
          success: false,
          error: "Streaming connection failed: #{e.message}",
          error_code: 'CONNECTION_ERROR',
          duration_ms: ((Time.current - start_time) * 1000).to_i
        }
      end
    end

    def parse_a2a_response(body, duration_ms)
      data = JSON.parse(body)

      # A2A response format
      status = data['status'] || {}
      state = status['state'] || 'completed'

      case state
      when 'completed'
        {
          success: true,
          output: extract_output_from_response(data),
          artifacts: data['artifacts'] || [],
          duration_ms: duration_ms,
          external_response: data
        }
      when 'failed'
        error = data['error'] || {}
        {
          success: false,
          error: error['message'] || 'External agent failed',
          error_code: error['code'] || 'EXTERNAL_FAILURE',
          duration_ms: duration_ms
        }
      when 'input-required'
        # Task needs input - update our task status
        {
          success: true,
          status: 'input_required',
          output: {
            'input_request' => data['message'],
            'prompt' => extract_text_from_message(data['message'])
          },
          duration_ms: duration_ms
        }
      when 'working', 'submitted'
        # Task is still in progress - need to poll
        {
          success: true,
          status: 'active',
          external_task_id: data['id'],
          duration_ms: duration_ms,
          poll_required: true
        }
      else
        {
          success: false,
          error: "Unknown A2A state: #{state}",
          error_code: 'UNKNOWN_STATE',
          duration_ms: duration_ms
        }
      end
    rescue JSON::ParserError => e
      {
        success: false,
        error: "Invalid JSON response from external agent: #{e.message}",
        error_code: 'INVALID_RESPONSE',
        duration_ms: duration_ms
      }
    end

    def parse_a2a_error(body, status_code, duration_ms)
      begin
        data = JSON.parse(body)
        error = data['error'] || data

        {
          success: false,
          error: error['message'] || "HTTP #{status_code}",
          error_code: error['code'] || "HTTP_#{status_code}",
          duration_ms: duration_ms
        }
      rescue JSON::ParserError
        {
          success: false,
          error: "HTTP #{status_code}: #{body.truncate(200)}",
          error_code: "HTTP_#{status_code}",
          duration_ms: duration_ms
        }
      end
    end

    def extract_output_from_response(data)
      message = data['message'] || {}

      {
        'content' => extract_text_from_message(message),
        'message' => message,
        'status' => data['status']
      }
    end

    def extract_text_from_message(message)
      return '' unless message.is_a?(Hash)

      parts = message['parts'] || []
      parts.select { |p| p['type'] == 'text' }
           .map { |p| p['text'] }
           .join("\n")
    end
  end
end

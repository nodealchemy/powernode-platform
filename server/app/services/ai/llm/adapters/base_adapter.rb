# frozen_string_literal: true

module Ai
  module Llm
    module Adapters
      # Abstract base class for LLM provider adapters
      # Handles HTTP setup, streaming infrastructure, and common error handling
      class BaseAdapter
        # Historical streaming read-timeout floor. Capability-aware read timeouts
        # (adaptive-only models → 600s) never drop below this, so legacy streaming
        # behaviour is preserved while long adaptive turns get their full budget.
        STREAM_READ_TIMEOUT_FLOOR = 300

        attr_reader :api_key, :base_url, :headers, :provider_name

        def initialize(api_key:, base_url:, provider_name:, extra_headers: {})
          @api_key = api_key
          @base_url = base_url.to_s.chomp("/")
          @provider_name = provider_name
          @headers = build_headers(extra_headers)
        end

        # @param messages [Array<Hash>] [{role:, content:}]
        # @param model [String] model ID
        # @param opts [Hash] max_tokens, temperature, system_prompt, etc.
        # @return [Ai::Llm::Response]
        def complete(messages:, model:, **opts)
          raise NotImplementedError
        end

        # @param messages [Array<Hash>]
        # @param model [String]
        # @param opts [Hash]
        # @yield [Ai::Llm::Chunk]
        # @return [Ai::Llm::Response] final accumulated response
        def stream(messages:, model:, **opts, &block)
          raise NotImplementedError
        end

        # @param messages [Array<Hash>]
        # @param tools [Array<Hash>] [{name:, description:, parameters:}]
        # @param model [String]
        # @param opts [Hash]
        # @return [Ai::Llm::Response]
        def complete_with_tools(messages:, tools:, model:, **opts)
          raise NotImplementedError
        end

        # @param messages [Array<Hash>]
        # @param schema [Hash] JSON Schema for output validation
        # @param model [String]
        # @param opts [Hash]
        # @return [Ai::Llm::Response]
        def complete_structured(messages:, schema:, model:, **opts)
          raise NotImplementedError
        end

        protected

        # Non-streaming HTTP POST via HTTParty. The per-request timeout is
        # capability-aware: adaptive-only/effort-capable models (Fable / Mythos /
        # Opus 4.7+ / Sonnet 5) can run for minutes, so they get the long timeout
        # from the model's capability profile (600s, aligned with the server→worker
        # envelope); legacy models keep 120s. `model` is nil-safe (→ 120s). Mirrors
        # worker/app/services/ai/llm/client.rb#http_post.
        def http_post(path, body, model = nil)
          url = "#{base_url}#{path}"
          response = HTTParty.post(
            url,
            headers: headers,
            body: body.to_json,
            timeout: Ai::Llm::ModelCapabilities.request_timeout_seconds(model)
          )
          [response.code, response.parsed_response, response.headers]
        end

        # Streaming HTTP POST via Net::HTTP — yields raw chunks. The read timeout is
        # capability-aware but never below STREAM_READ_TIMEOUT_FLOOR: an
        # adaptive-only/effort turn (Fable etc.) may go past 300s before the next
        # chunk, so it gets its 600s profile timeout; every other model keeps 300s.
        def http_stream(path, body, model = nil)
          uri = URI.parse("#{base_url}#{path}")
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == "https"
          http.read_timeout = [
            Ai::Llm::ModelCapabilities.request_timeout_seconds(model),
            STREAM_READ_TIMEOUT_FLOOR
          ].max
          http.open_timeout = 30

          request = Net::HTTP::Post.new(uri.request_uri)
          headers.each { |k, v| request[k] = v }
          request.body = body.to_json

          http.request(request) do |response|
            unless response.is_a?(Net::HTTPSuccess)
              error_body = response.body
              raise RequestError.new(
                "HTTP #{response.code}: #{error_body}",
                status_code: response.code.to_i
              )
            end
            yield response
          end
        end

        # Parse SSE event stream — yields parsed JSON objects
        def parse_sse_stream(response, &block)
          buffer = ""
          response.read_body do |chunk|
            buffer += chunk
            while (event_end = buffer.index("\n\n"))
              event_data = buffer[0...event_end]
              buffer = buffer[(event_end + 2)..]

              event_data.split("\n").each do |line|
                next unless line.start_with?("data: ")

                json_str = line[6..]
                next if json_str == "[DONE]"

                begin
                  yield JSON.parse(json_str)
                rescue JSON::ParserError => e
                  Rails.logger.warn "[LLM] Failed to parse SSE chunk: #{e.message}"
                end
              end
            end
          end
        end

        # Parse NDJSON stream — yields parsed JSON objects
        def parse_ndjson_stream(response, &block)
          buffer = ""
          response.read_body do |chunk|
            buffer += chunk
            while (line_end = buffer.index("\n"))
              json_line = buffer[0...line_end].strip
              buffer = buffer[(line_end + 1)..]
              next if json_line.empty?

              begin
                yield JSON.parse(json_line)
              rescue JSON::ParserError => e
                Rails.logger.warn "[LLM] Failed to parse NDJSON: #{e.message}"
              end
            end
          end
        end

        def build_headers(extra = {})
          { "Content-Type" => "application/json", "User-Agent" => "Powernode-AI/2.0" }.merge(extra)
        end

        def build_response(attrs)
          Ai::Llm::Response.new(attrs.merge(provider: provider_name))
        end

        def build_error_response(error, status_code: nil)
          # Surface upstream errors at error-level so callers can grep
          # journalctl instead of having to inspect raw_response[:error]
          # on the returned response object. Keeps debugging short for
          # provider 4xx/5xx, rate limits, model-not-found, etc.
          Rails.logger.error "[LLM #{provider_name}] error response: status=#{status_code || 'n/a'} msg=#{error}"

          Ai::Llm::Response.new(
            content: nil,
            provider: provider_name,
            finish_reason: "error",
            raw_response: { error: error, status_code: status_code }
          )
        end

        # Default provider error handler — reads {error:{message:}} or {error:}
        # from the parsed body. Anthropic and OpenAI share this exactly; Ollama
        # overrides it for its flatter error shape.
        def handle_error(status, parsed)
          error_msg = if parsed.is_a?(Hash)
                        parsed.dig("error", "message") || parsed["error"] || "Unknown error"
                      else
                        parsed.to_s
                      end
          error_msg = error_msg.to_json if error_msg.is_a?(Hash)

          build_error_response("#{error_msg} (HTTP #{status})", status_code: status)
        end

        # Best-effort JSON parse: returns the parsed object, or the original
        # value unchanged if it isn't a parseable JSON string.
        def safe_parse_json(str)
          return str unless str.is_a?(String)

          JSON.parse(str)
        rescue JSON::ParserError
          str
        end
      end

      # Custom error class for adapter HTTP errors
      class RequestError < StandardError
        attr_reader :status_code

        def initialize(message, status_code: nil)
          @status_code = status_code
          super(message)
        end
      end
    end
  end
end

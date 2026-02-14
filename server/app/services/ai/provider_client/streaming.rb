# frozen_string_literal: true

class Ai::ProviderClientService
  module Streaming
    extend ActiveSupport::Concern

    private

    # Stream response using Server-Sent Events (SSE) for OpenAI/Anthropic
    # @param url [String] Full URL to send request to
    # @param body [Hash] Request body
    # @param provider_type [Symbol] :openai or :anthropic for parsing
    # @yieldparam chunk [Hash] Parsed chunk with :type, :content, :done, :usage
    def stream_response_with_sse(url, body, provider_type, &block)
      raise ArgumentError, "Block required for streaming" unless block_given?

      require "net/http"
      require "uri"

      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.read_timeout = 120
      http.open_timeout = 30

      request = Net::HTTP::Post.new(uri.request_uri)
      @headers.each { |k, v| request[k] = v }
      request.body = body.to_json

      accumulated_content = ""
      usage_data = {}
      stream_id = SecureRandom.uuid

      begin
        http.request(request) do |response|
          unless response.is_a?(Net::HTTPSuccess)
            error_body = response.body
            yield({
              type: :error,
              error: "HTTP #{response.code}: #{error_body}",
              stream_id: stream_id
            })
            return {
              success: false,
              error: "HTTP #{response.code}",
              status_code: response.code.to_i
            }
          end

          # Yield stream start event
          yield({
            type: :stream_start,
            stream_id: stream_id,
            timestamp: Time.current.iso8601
          })

          buffer = ""
          response.read_body do |chunk|
            buffer += chunk

            # Process complete SSE events (separated by double newlines)
            while (event_end = buffer.index("\n\n"))
              event_data = buffer[0...event_end]
              buffer = buffer[(event_end + 2)..]

              # Parse SSE format: "data: {...}"
              event_data.split("\n").each do |line|
                next unless line.start_with?("data: ")

                json_str = line[6..] # Remove "data: " prefix
                next if json_str == "[DONE]"

                begin
                  parsed = JSON.parse(json_str)
                  chunk_result = parse_sse_chunk(parsed, provider_type)

                  if chunk_result[:content]
                    accumulated_content += chunk_result[:content]
                    yield({
                      type: :content_delta,
                      content: chunk_result[:content],
                      accumulated_content: accumulated_content,
                      stream_id: stream_id,
                      timestamp: Time.current.iso8601
                    })
                  end

                  if chunk_result[:usage]
                    usage_data = chunk_result[:usage]
                  end

                  if chunk_result[:done]
                    yield({
                      type: :stream_end,
                      content: accumulated_content,
                      usage: usage_data,
                      stream_id: stream_id,
                      timestamp: Time.current.iso8601
                    })
                  end
                rescue JSON::ParserError => e
                  Rails.logger.warn "[STREAMING] Failed to parse SSE chunk: #{e.message}"
                end
              end
            end
          end
        end

        {
          success: true,
          content: accumulated_content,
          usage: usage_data,
          stream_id: stream_id
        }
      rescue Net::OpenTimeout, Net::ReadTimeout => e
        yield({
          type: :error,
          error: "Timeout: #{e.message}",
          stream_id: stream_id
        })
        { success: false, error: e.message }
      rescue StandardError => e
        Rails.logger.error "[STREAMING] Stream error: #{e.message}"
        yield({
          type: :error,
          error: e.message,
          stream_id: stream_id
        })
        { success: false, error: e.message }
      end
    end

    # Stream response using newline-delimited JSON (NDJSON) for Ollama
    # @param url [String] Full URL to send request to
    # @param body [Hash] Request body
    # @yieldparam chunk [Hash] Parsed chunk with :type, :content, :done
    def stream_response_with_ndjson(url, body, headers = {}, &block)
      raise ArgumentError, "Block required for streaming" unless block_given?

      require "net/http"
      require "uri"

      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.read_timeout = 300 # Ollama can be slow for large models
      http.open_timeout = 30

      request = Net::HTTP::Post.new(uri.request_uri)
      request["Content-Type"] = "application/json"
      headers.each { |k, v| request[k] = v }
      request.body = body.to_json

      accumulated_content = ""
      stream_id = SecureRandom.uuid

      begin
        http.request(request) do |response|
          unless response.is_a?(Net::HTTPSuccess)
            yield({
              type: :error,
              error: "HTTP #{response.code}",
              stream_id: stream_id
            })
            return { success: false, error: "HTTP #{response.code}" }
          end

          yield({
            type: :stream_start,
            stream_id: stream_id,
            timestamp: Time.current.iso8601
          })

          buffer = ""
          response.read_body do |chunk|
            buffer += chunk

            # Process complete JSON lines
            while (line_end = buffer.index("\n"))
              json_line = buffer[0...line_end].strip
              buffer = buffer[(line_end + 1)..]

              next if json_line.empty?

              begin
                parsed = JSON.parse(json_line)

                if parsed["message"] && parsed["message"]["content"]
                  content = parsed["message"]["content"]
                  accumulated_content += content
                  yield({
                    type: :content_delta,
                    content: content,
                    accumulated_content: accumulated_content,
                    stream_id: stream_id,
                    timestamp: Time.current.iso8601
                  })
                end

                if parsed["done"]
                  yield({
                    type: :stream_end,
                    content: accumulated_content,
                    usage: {
                      prompt_tokens: parsed["prompt_eval_count"],
                      completion_tokens: parsed["eval_count"],
                      total_tokens: (parsed["prompt_eval_count"] || 0) + (parsed["eval_count"] || 0)
                    },
                    stream_id: stream_id,
                    timestamp: Time.current.iso8601
                  })
                end
              rescue JSON::ParserError => e
                Rails.logger.warn "[STREAMING] Failed to parse NDJSON: #{e.message}"
              end
            end
          end
        end

        { success: true, content: accumulated_content, stream_id: stream_id }
      rescue StandardError => e
        Rails.logger.error "[STREAMING] Ollama stream error: #{e.message}"
        yield({ type: :error, error: e.message, stream_id: stream_id })
        { success: false, error: e.message }
      end
    end

    # Parse SSE chunk based on provider type
    # @param parsed [Hash] Parsed JSON from SSE data line
    # @param provider_type [Symbol] :openai or :anthropic
    # @return [Hash] Normalized chunk with :content, :done, :usage
    def parse_sse_chunk(parsed, provider_type)
      case provider_type
      when :openai
        parse_openai_sse_chunk(parsed)
      when :anthropic
        parse_anthropic_sse_chunk(parsed)
      else
        { content: nil, done: false }
      end
    end
  end
end

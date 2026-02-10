# frozen_string_literal: true

module Ai
  module Llm
    # Normalized response object from any LLM provider
    # Provides a consistent interface regardless of whether the call
    # went to OpenAI, Anthropic, or Ollama
    class Response
      attr_reader :content, :tool_calls, :finish_reason, :model, :provider,
                  :usage, :cost, :thinking_content, :raw_response, :stream_id

      def initialize(attrs = {})
        @content = attrs[:content]
        @tool_calls = attrs[:tool_calls] || []
        @finish_reason = attrs[:finish_reason]
        @model = attrs[:model]
        @provider = attrs[:provider]
        @usage = normalize_usage(attrs[:usage] || {})
        @cost = attrs[:cost] || 0.0
        @thinking_content = attrs[:thinking_content]
        @raw_response = attrs[:raw_response]
        @stream_id = attrs[:stream_id]
      end

      def success?
        content.present? || tool_calls.any?
      end

      def has_tool_calls?
        tool_calls.any?
      end

      def total_tokens
        usage[:total_tokens] || 0
      end

      def prompt_tokens
        usage[:prompt_tokens] || 0
      end

      def completion_tokens
        usage[:completion_tokens] || 0
      end

      def cached_tokens
        usage[:cached_tokens] || 0
      end

      def to_h
        {
          content: content,
          tool_calls: tool_calls,
          finish_reason: finish_reason,
          model: model,
          provider: provider,
          usage: usage,
          cost: cost,
          thinking_content: thinking_content,
          stream_id: stream_id
        }.compact
      end

      private

      def normalize_usage(raw)
        {
          prompt_tokens: raw[:prompt_tokens] || raw[:input_tokens] || 0,
          completion_tokens: raw[:completion_tokens] || raw[:output_tokens] || 0,
          cached_tokens: raw[:cached_tokens] || raw[:cache_read_input_tokens] || 0,
          total_tokens: raw[:total_tokens] || (
            (raw[:prompt_tokens] || raw[:input_tokens] || 0) +
            (raw[:completion_tokens] || raw[:output_tokens] || 0)
          )
        }
      end
    end

    # Chunk yielded during streaming
    Chunk = Data.define(
      :type,           # :content_delta, :tool_call_start, :tool_call_delta, :tool_call_end,
                       # :stream_start, :stream_end, :error, :thinking_delta
      :content,        # Text content for content_delta
      :tool_call_id,   # For tool_call_* events
      :tool_call_name, # For tool_call_start
      :tool_call_args_delta, # For tool_call_delta (partial JSON)
      :done,           # Boolean — true on stream_end
      :usage,          # Hash on stream_end
      :stream_id,      # UUID for the stream
      :timestamp       # ISO8601 timestamp
    ) do
      def initialize(type:, content: nil, tool_call_id: nil, tool_call_name: nil,
                     tool_call_args_delta: nil, done: false, usage: nil,
                     stream_id: nil, timestamp: nil)
        super
      end
    end
  end
end

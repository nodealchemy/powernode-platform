# frozen_string_literal: true

module Ai
  module Llm
    # Normalized response object from any LLM provider
    # Provides a consistent interface regardless of whether the call
    # went to OpenAI, Anthropic, or Ollama
    class Response
      attr_reader :content, :tool_calls, :finish_reason, :model, :provider,
                  :usage, :cost, :thinking_content, :raw_response, :stream_id,
                  :refusal, :content_blocks

      # `served_by` (model that ultimately produced the content) and
      # `refusal_recovery` (the adapt→fallback audit trail) are set AFTER
      # construction by Ai::Llm::RefusalHandler (worker) and read back off the
      # worker JSON by WorkerLlmClient, so they are writable.
      attr_accessor :served_by, :refusal_recovery

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
        # Structured safety-classifier refusal (HTTP 200, stop_reason "refusal").
        # A Hash {stop_reason, category, explanation, phase} when the model
        # DECLINED, else nil. Detection sets this BEFORE any content is read so
        # a refusal never returns as a silent nil.
        @refusal = attrs[:refusal]
        # The assistant turn's raw Anthropic blocks (thinking included), in order,
        # when it carries thinking; a tool loop replays them verbatim. nil otherwise.
        @content_blocks = attrs[:content_blocks]
        @served_by = attrs[:served_by]
        @refusal_recovery = attrs[:refusal_recovery]
      end

      # True when the response the caller receives is itself a refusal (the
      # requested model declined and no fallback resolved it). Callers MUST
      # branch on this before treating empty content as an error.
      def refused?
        !@refusal.nil?
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

      def cache_creation_tokens
        usage[:cache_creation_tokens] || 0
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
          stream_id: stream_id,
          refusal: refusal,
          content_blocks: content_blocks,
          served_by: served_by,
          refusal_recovery: refusal_recovery
        }.compact
      end

      private

      # INVARIANT, every provider: prompt_tokens is the TOTAL input, and
      # cached_tokens (cache reads) and cache_creation_tokens (cache writes) are
      # SUBSETS of it. OpenAI reports it that way; the Anthropic parsers sum
      # Anthropic's uncached input_tokens with both cache counts
      # (AnthropicMessages.usage). Ai::CostCalculationService prices
      # prompt - cached - cache_creation at the input rate.
      def normalize_usage(raw)
        cached = raw[:cached_tokens] || raw[:cache_read_input_tokens] || 0
        # Anthropic cache WRITES (billed above the base input rate); 0 elsewhere.
        creation = raw[:cache_creation_tokens] || raw[:cache_creation_input_tokens] || 0
        # Raw Anthropic keys: input_tokens is the uncached remainder, so the total
        # adds the cache counts (the invariant above).
        prompt = raw[:prompt_tokens] || (raw.key?(:input_tokens) ? raw[:input_tokens].to_i + cached + creation : 0)
        completion = raw[:completion_tokens] || raw[:output_tokens] || 0
        {
          prompt_tokens: prompt,
          completion_tokens: completion,
          cached_tokens: cached,
          cache_creation_tokens: creation,
          total_tokens: raw[:total_tokens] || (prompt + completion)
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

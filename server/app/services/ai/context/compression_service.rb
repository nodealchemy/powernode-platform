# frozen_string_literal: true

module Ai
  module Context
    class CompressionService
      include Ai::Concerns::PromptTemplateLookup
      include AgentBackedService

      CHARS_PER_TOKEN = 4
      MAX_ENTRY_TOKENS = 500
      COMPRESSION_RATIO_TARGET = 0.5

      PROMPT_SLUG = "ai-context-compression"
      FALLBACK_PROMPT = "Compress the following text to roughly half its length while preserving all key facts, names, and numbers. Output only the compressed text."

      def initialize(account:)
        @account = account
      end

      # Compress verbose context entries to fit within token budget
      def compress_entries(entries:, token_budget:)
        return { entries: entries, compressed: 0, original_tokens: 0, compressed_tokens: 0 } if entries.empty?

        original_tokens = estimate_tokens(entries)
        return { entries: entries, compressed: 0, original_tokens: original_tokens, compressed_tokens: original_tokens } if original_tokens <= token_budget

        compressed_entries = []
        compressed_count = 0

        entries.each do |entry|
          entry_tokens = (entry[:content].to_s.length / CHARS_PER_TOKEN.to_f).ceil

          if entry_tokens > MAX_ENTRY_TOKENS
            compressed = compress_single(entry)
            compressed_entries << compressed
            compressed_count += 1
          else
            compressed_entries << entry
          end
        end

        {
          entries: compressed_entries,
          compressed: compressed_count,
          original_tokens: original_tokens,
          compressed_tokens: estimate_tokens(compressed_entries)
        }
      end

      # Compress a single entry using extractive summarization
      def compress_single(entry)
        content = entry[:content].to_s
        return entry if content.length < MAX_ENTRY_TOKENS * CHARS_PER_TOKEN

        # Try LLM compression
        compressed = llm_compress(content)
        if compressed
          return entry.merge(
            content: compressed,
            metadata: (entry[:metadata] || {}).merge(
              compressed: true,
              original_length: content.length,
              compressed_at: Time.current.iso8601
            )
          )
        end

        # Fallback: extractive compression (keep key sentences)
        sentences = content.split(/(?<=[.!?])\s+/)
        target_count = [(sentences.size * COMPRESSION_RATIO_TARGET).ceil, 1].max
        kept = sentences.first(target_count)

        entry.merge(
          content: kept.join(" "),
          metadata: (entry[:metadata] || {}).merge(
            compressed: true,
            compression_method: "extractive",
            original_length: content.length
          )
        )
      end

      private

      def estimate_tokens(entries)
        entries.sum { |e| (e[:content].to_s.length / CHARS_PER_TOKEN.to_f).ceil }
      end

      def llm_compress(content)
        client = find_economy_client
        return nil unless client

        agent = @economy_agent
        baseline_model = agent && agent_model(agent)
        return nil unless baseline_model

        system_content = resolve_prompt_template(
          PROMPT_SLUG,
          account: @account,
          fallback: FALLBACK_PROMPT
        )
        messages = [
          { role: "system", content: system_content },
          { role: "user", content: content.truncate(2000) }
        ]

        model = baseline_model
        effort = nil

        # inc4: governed per-task tier routing ("summarization" — bulk context
        # compression has no escalation basis of its own). Gated OFF by default
        # ⇒ resolve_task_tier returns nil, model/effort unchanged.
        if (resolution = resolve_task_tier(agent: agent, task_type: "summarization", messages: messages))
          model = resolution.model.presence || model
          effort = resolution.effort
        end

        response = client.complete(
          messages: messages,
          model: model,
          max_tokens: (content.length / (CHARS_PER_TOKEN * 2)),
          temperature: 0.1,
          **({ effort: effort, routing_decision_id: routing_decision_id }.compact)
        )

        response.success? ? response.content : nil
      rescue StandardError => e
        Rails.logger.warn "[ContextCompression] LLM compression failed: #{e.message}"
        nil
      end

      # Returns the WorkerLlmClient for the economy agent, memoizing the agent
      # itself in @economy_agent so #llm_compress can resolve a baseline model
      # from it (previously read a never-assigned @economy_credential ivar,
      # which meant this LLM-compression path always raised and silently fell
      # back to extractive compression — fixed here as part of threading tier
      # routing through, since that requires a real agent/model baseline).
      def find_economy_client
        return @economy_client if defined?(@economy_client)

        agent = discover_service_agent(
          "Compress verbose context entries while preserving key facts and structure",
          fallback_slug: nil
        )
        # Fall back to any active agent — compression is a lightweight utility call
        agent ||= @account.ai_agents.active.first
        @economy_agent = agent
        @economy_client = agent ? build_agent_client(agent) : nil
      end
    end
  end
end

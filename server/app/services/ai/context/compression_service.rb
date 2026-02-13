# frozen_string_literal: true

module Ai
  module Context
    class CompressionService
      CHARS_PER_TOKEN = 4
      MAX_ENTRY_TOKENS = 500
      COMPRESSION_RATIO_TARGET = 0.5

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
        provider = find_economy_provider
        return nil unless provider

        response = provider.generate(
          messages: [
            { role: "system", content: "Compress the following text to roughly half its length while preserving all key facts, names, and numbers. Output only the compressed text." },
            { role: "user", content: content.truncate(2000) }
          ],
          max_tokens: (content.length / (CHARS_PER_TOKEN * 2)),
          temperature: 0.1
        )

        response&.dig(:content)
      rescue StandardError => e
        Rails.logger.warn "[ContextCompression] LLM compression failed: #{e.message}"
        nil
      end

      def find_economy_provider
        return @economy_provider if defined?(@economy_provider)

        @economy_provider = begin
          credential = Ai::ProviderCredential.joins(:ai_provider)
            .where(account_id: @account.id, is_active: true)
            .where(ai_providers: { provider_type: "text_generation" })
            .order(:priority_order)
            .first

          Ai::ProviderClientService.new(credential: credential) if credential
        end
      end
    end
  end
end

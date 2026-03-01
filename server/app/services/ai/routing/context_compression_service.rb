# frozen_string_literal: true

module Ai
  module Routing
    # Service for compressing conversation context to reduce token usage.
    #
    # Supports multiple compression strategies:
    # - :extractive  — Keep important messages verbatim, drop the rest
    # - :hierarchical — Keep recent messages verbatim, summarize older ones
    # - :selective   — Drop low-importance messages entirely
    # - :auto        — Automatically pick the best strategy
    #
    # Usage:
    #   service = Ai::Routing::ContextCompressionService.new(account: account)
    #   result = service.compress(messages: messages, token_budget: 2000)
    #   result[:compressed_messages]  # => [...]
    #   result[:compression_ratio]    # => 0.45
    #
    class ContextCompressionService
      include Ai::Concerns::AccountScoped

      STRATEGIES = %i[extractive hierarchical selective auto].freeze

      # Message importance weights by role
      ROLE_IMPORTANCE = {
        "system" => 1.0,
        "user" => 0.8,
        "assistant" => 0.6,
        "tool" => 0.4
      }.freeze

      # Minimum messages to preserve regardless of budget
      MIN_PRESERVED_MESSAGES = 2

      # Compress conversation messages to fit within a token budget.
      #
      # @param messages [Array<Hash>] Messages with :role and :content
      # @param token_budget [Integer] Maximum tokens for compressed output
      # @param strategy [Symbol] Compression strategy (:extractive, :hierarchical, :selective, :auto)
      # @return [Hash] Compressed result with messages, token counts, and ratio
      def compress(messages:, token_budget:, strategy: :auto)
        return empty_result(messages) if messages.empty?

        original_tokens = estimate_total_tokens(messages)

        # If already within budget, return as-is
        if original_tokens <= token_budget
          return {
            compressed_messages: messages,
            original_tokens: original_tokens,
            compressed_tokens: original_tokens,
            compression_ratio: 1.0,
            strategy_used: :none,
            messages_removed: 0
          }
        end

        effective_strategy = strategy == :auto ? select_strategy(messages, token_budget, original_tokens) : strategy

        compressed = case effective_strategy
                     when :extractive
                       compress_extractive(messages, token_budget)
                     when :hierarchical
                       compress_hierarchical(messages, token_budget)
                     when :selective
                       compress_selective(messages, token_budget)
                     else
                       compress_selective(messages, token_budget)
                     end

        compressed_tokens = estimate_total_tokens(compressed[:messages])

        {
          compressed_messages: compressed[:messages],
          original_tokens: original_tokens,
          compressed_tokens: compressed_tokens,
          compression_ratio: original_tokens > 0 ? (compressed_tokens.to_f / original_tokens).round(4) : 1.0,
          strategy_used: effective_strategy,
          messages_removed: messages.length - compressed[:messages].length
        }
      end

      private

      def empty_result(messages)
        {
          compressed_messages: messages,
          original_tokens: 0,
          compressed_tokens: 0,
          compression_ratio: 1.0,
          strategy_used: :none,
          messages_removed: 0
        }
      end

      def select_strategy(messages, token_budget, original_tokens)
        ratio_needed = token_budget.to_f / original_tokens

        if ratio_needed > 0.7
          # Light compression needed - just drop low-importance messages
          :selective
        elsif ratio_needed > 0.3
          # Moderate compression - summarize old, keep recent
          :hierarchical
        else
          # Heavy compression - keep only the most important
          :extractive
        end
      end

      # Extractive: Score each message by importance, keep top-scoring ones
      def compress_extractive(messages, token_budget)
        scored = messages.each_with_index.map do |msg, idx|
          {
            message: msg,
            index: idx,
            importance: calculate_importance(msg, idx, messages.length),
            tokens: estimate_message_tokens(msg)
          }
        end

        # Always keep system messages and the last user message
        required = scored.select { |s| s[:message][:role] == "system" || s[:message]["role"] == "system" }
        last_user = scored.reverse.detect { |s| (s[:message][:role] || s[:message]["role"]) == "user" }
        required << last_user if last_user && !required.include?(last_user)

        required_tokens = required.sum { |s| s[:tokens] }
        remaining_budget = token_budget - required_tokens

        # Fill remaining budget with highest importance messages
        optional = scored - required
        optional.sort_by! { |s| -s[:importance] }

        selected = required.dup
        optional.each do |scored_msg|
          break if remaining_budget <= 0

          if scored_msg[:tokens] <= remaining_budget
            selected << scored_msg
            remaining_budget -= scored_msg[:tokens]
          end
        end

        # Restore original order
        selected.sort_by! { |s| s[:index] }

        { messages: selected.map { |s| s[:message] } }
      end

      # Hierarchical: Keep recent messages verbatim, compress older ones into a summary
      def compress_hierarchical(messages, token_budget)
        return { messages: messages } if messages.length <= MIN_PRESERVED_MESSAGES

        # Determine split point - keep last ~40% verbatim
        split_index = [(messages.length * 0.6).ceil, messages.length - MIN_PRESERVED_MESSAGES].min
        split_index = [split_index, 0].max

        older_messages = messages[0...split_index]
        recent_messages = messages[split_index..]

        recent_tokens = estimate_total_tokens(recent_messages)

        if recent_tokens >= token_budget
          # Even recent messages exceed budget, fall back to extractive
          return compress_extractive(messages, token_budget)
        end

        # Compress older messages into a summary
        summary_budget = token_budget - recent_tokens
        summary = generate_summary(older_messages, summary_budget)

        compressed = []
        # Preserve system messages from older set
        older_messages.each do |msg|
          role = msg[:role] || msg["role"]
          compressed << msg if role == "system"
        end

        # Add summary as a system context message
        if summary.present?
          compressed << {
            role: "system",
            content: "[Conversation Summary] #{summary}"
          }
        end

        compressed.concat(recent_messages)

        { messages: compressed }
      end

      # Selective: Drop low-importance messages entirely
      def compress_selective(messages, token_budget)
        scored = messages.each_with_index.map do |msg, idx|
          {
            message: msg,
            index: idx,
            importance: calculate_importance(msg, idx, messages.length),
            tokens: estimate_message_tokens(msg)
          }
        end

        # Sort by importance (ascending) so we drop least important first
        by_importance = scored.sort_by { |s| s[:importance] }

        current_tokens = scored.sum { |s| s[:tokens] }
        dropped_indices = Set.new

        by_importance.each do |scored_msg|
          break if current_tokens <= token_budget
          break if scored.length - dropped_indices.length <= MIN_PRESERVED_MESSAGES

          role = scored_msg[:message][:role] || scored_msg[:message]["role"]
          # Never drop system messages or the last message
          next if role == "system"
          next if scored_msg[:index] == messages.length - 1

          dropped_indices << scored_msg[:index]
          current_tokens -= scored_msg[:tokens]
        end

        kept = scored.reject { |s| dropped_indices.include?(s[:index]) }
        kept.sort_by! { |s| s[:index] }

        { messages: kept.map { |s| s[:message] } }
      end

      def calculate_importance(message, index, total_messages)
        role = message[:role] || message["role"] || "user"
        content = message[:content] || message["content"] || ""

        # Base importance from role
        importance = ROLE_IMPORTANCE[role] || 0.5

        # Recency boost: more recent messages are more important
        recency = total_messages > 1 ? (index.to_f / (total_messages - 1)) : 1.0
        importance += recency * 0.3

        # Content length factor: very short messages are less important (unless system)
        if role != "system"
          token_count = estimate_tokens(content)
          importance -= 0.1 if token_count < 10
          importance += 0.1 if token_count > 200
        end

        # System messages always maximum importance
        importance = 1.5 if role == "system"

        importance.clamp(0.0, 2.0)
      end

      def generate_summary(messages, max_tokens)
        # Simple extractive summary: take first sentence from each message
        parts = messages.filter_map do |msg|
          role = msg[:role] || msg["role"]
          content = msg[:content] || msg["content"] || ""
          next if content.blank?
          next if role == "system"

          first_sentence = content.split(/[.!?]\s/).first&.strip
          next if first_sentence.blank?

          "#{role.capitalize}: #{first_sentence}."
        end

        summary = parts.join(" ")

        # Truncate to fit budget
        max_chars = max_tokens * 4
        if summary.length > max_chars
          summary = summary[0...max_chars].rstrip
          summary = "#{summary}..."
        end

        summary
      end

      def estimate_message_tokens(message)
        content = message[:content] || message["content"] || ""
        # Token overhead for role and message structure
        estimate_tokens(content) + 4
      end

      def estimate_total_tokens(messages)
        messages.sum { |m| estimate_message_tokens(m) }
      end

      def estimate_tokens(text)
        (text.to_s.length / 4.0).ceil
      end
    end
  end
end

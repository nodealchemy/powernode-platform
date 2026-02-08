# frozen_string_literal: true

module Ai
  module Memory
    class SharedLearningService
      LEARNING_CATEGORIES = %w[fact pattern anti_pattern best_practice discovery].freeze

      LEARNING_MARKERS = {
        "Discovery:" => "discovery",
        "Pattern:" => "pattern",
        "Anti-pattern:" => "anti_pattern",
        "Best practice:" => "best_practice",
        "Fact:" => "fact"
      }.freeze

      attr_reader :account

      def initialize(account:)
        @account = account
      end

      # Record a single learning entry to a memory pool
      def record_learning(pool:, category:, content:, agent_id: nil)
        return unless LEARNING_CATEGORIES.include?(category)

        learnings = pool.data["learnings"] || []
        learnings << {
          "category" => category,
          "content" => content,
          "agent_id" => agent_id,
          "importance" => calculate_importance(content, category),
          "recorded_at" => Time.current.iso8601
        }

        pool.data["learnings"] = learnings
        pool.last_accessed_at = Time.current
        pool.save!

        Rails.logger.info("[SharedLearning] Recorded #{category} learning in pool #{pool.pool_id}")
      end

      # Extract learnings from agent output using marker patterns
      def extract_learnings_from_output(output:, agent_id: nil)
        return [] if output.blank?

        text = output.is_a?(Hash) ? (output["text"] || output[:text] || output.to_json) : output.to_s
        learnings = []

        LEARNING_MARKERS.each do |marker, category|
          text.scan(/#{Regexp.escape(marker)}\s*(.+?)(?:\n|$)/i).each do |match|
            content = match[0].strip
            next if content.blank?

            learnings << {
              category: category,
              content: content,
              agent_id: agent_id
            }
          end
        end

        learnings
      end

      # Full pipeline: extract learnings from output and record them
      def process_completed_task(pool:, output:, agent_id: nil)
        learnings = extract_learnings_from_output(output: output, agent_id: agent_id)

        learnings.each do |learning|
          record_learning(
            pool: pool,
            category: learning[:category],
            content: learning[:content],
            agent_id: learning[:agent_id]
          )
        end

        Rails.logger.info("[SharedLearning] Processed #{learnings.size} learnings from task output")
        learnings.size
      end

      # Promote high-importance learnings from an execution pool to the global pool
      def promote_to_global(execution_pool:, min_importance: 0.7)
        global_pool = ensure_global_learning_pool
        learnings = execution_pool.data["learnings"] || []

        promoted = learnings.select { |l| (l["importance"] || 0) >= min_importance }
        return 0 if promoted.empty?

        global_learnings = global_pool.data["learnings"] || []

        promoted.each do |learning|
          # Avoid duplicates by checking content similarity
          next if global_learnings.any? { |gl| gl["content"] == learning["content"] }

          global_learnings << learning.merge(
            "promoted_from" => execution_pool.pool_id,
            "promoted_at" => Time.current.iso8601
          )
        end

        global_pool.data["learnings"] = global_learnings
        global_pool.last_accessed_at = Time.current
        global_pool.save!

        Rails.logger.info("[SharedLearning] Promoted #{promoted.size} learnings to global pool")
        promoted.size
      end

      # Retrieve relevant learnings using keyword-based search
      def retrieve_relevant_learnings(query:, limit: 10)
        return [] if query.blank?

        global_pool = find_global_learning_pool
        return [] unless global_pool

        all_learnings = global_pool.data["learnings"] || []
        return [] if all_learnings.empty?

        keywords = query.downcase.split(/\s+/).reject { |w| w.length < 3 }
        return all_learnings.first(limit) if keywords.empty?

        # Score learnings by keyword relevance
        scored = all_learnings.map do |learning|
          content_lower = (learning["content"] || "").downcase
          score = keywords.count { |kw| content_lower.include?(kw) }
          importance = learning["importance"] || 0.5
          { learning: learning, score: score + importance }
        end

        scored
          .select { |s| s[:score] > 0 }
          .sort_by { |s| -s[:score] }
          .first(limit)
          .map { |s| s[:learning] }
      end

      # Format learnings for LLM prompt injection
      def build_learning_context(query:, max_chars: 2000)
        learnings = retrieve_relevant_learnings(query: query, limit: 20)
        return nil if learnings.empty?

        lines = ["## Shared Learnings"]
        used = lines.first.length + 2

        learnings.each do |learning|
          category = learning["category"]
          content = learning["content"]
          line = "- [#{category}] #{content}"
          break if used + line.length > max_chars

          lines << line
          used += line.length + 1
        end

        return nil if lines.size == 1

        lines.join("\n")
      end

      private

      def calculate_importance(content, category)
        base = case category
               when "anti_pattern" then 0.9
               when "best_practice" then 0.8
               when "pattern" then 0.7
               when "discovery" then 0.6
               when "fact" then 0.5
               else 0.5
               end

        # Boost for longer, more detailed content
        length_boost = [content.to_s.length / 500.0, 0.1].min
        (base + length_boost).round(2)
      end

      def ensure_global_learning_pool
        pool_service = MemoryPoolService.new(account: account)
        pool_service.ensure_global_learning_pool
      end

      def find_global_learning_pool
        Ai::MemoryPool.where(account: account, pool_type: "global", scope: "persistent")
                      .where("name LIKE ?", "%Global Learnings%")
                      .first
      end
    end
  end
end

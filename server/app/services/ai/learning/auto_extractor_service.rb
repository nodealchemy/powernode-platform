# frozen_string_literal: true

module Ai
  module Learning
    class AutoExtractorService
      def initialize(account:)
        @account = account
      end

      # Extract learnings from a successful execution
      def extract_from_success(output:, metadata: {})
        learnings = []
        return learnings if output.blank?

        text = normalize_output(output)
        duration_ms = metadata[:duration_ms] || metadata["duration_ms"]
        cost_usd = metadata[:total_cost_usd] || metadata["total_cost_usd"]
        discovered_skill_ids = metadata[:discovered_skill_ids] || metadata["discovered_skill_ids"]

        # Performance insights
        if duration_ms.present? && duration_ms < 5000
          learnings << build_learning(
            category: "performance_insight",
            content: "Fast execution completed in #{duration_ms}ms. Configuration: #{metadata[:team_name] || 'unknown team'}",
            title: "Fast execution pattern",
            importance: 0.6,
            confidence: 0.7,
            extraction_method: "auto_success",
            skill_node_ids: discovered_skill_ids
          )
        end

        # Cost efficiency pattern
        if cost_usd.present? && cost_usd < 0.01 && text.length > 200
          learnings << build_learning(
            category: "best_practice",
            content: "Cost-efficient execution ($#{cost_usd}) produced substantial output (#{text.length} chars)",
            title: "Cost efficiency pattern",
            importance: 0.6,
            confidence: 0.6,
            extraction_method: "auto_success",
            skill_node_ids: discovered_skill_ids
          )
        end

        # Zero-failure patterns from task results
        tasks_completed = metadata[:tasks_completed] || metadata["tasks_completed"]
        tasks_failed = metadata[:tasks_failed] || metadata["tasks_failed"]
        if tasks_completed.to_i > 2 && tasks_failed.to_i == 0
          learnings << build_learning(
            category: "pattern",
            content: "All #{tasks_completed} tasks completed without failures. Team configuration is reliable for this type of work.",
            title: "Zero-failure execution",
            importance: 0.65,
            confidence: 0.75,
            extraction_method: "auto_success",
            skill_node_ids: discovered_skill_ids
          )
        end

        learnings
      end

      # Extract learnings from a failed execution
      def extract_from_failure(error:, metadata: {})
        learnings = []
        return learnings if error.blank?

        error_text = error.is_a?(String) ? error : error.to_s

        # Classify error type
        category_info = classify_error(error_text)

        learnings << build_learning(
          category: "failure_mode",
          content: "#{category_info[:label]}: #{error_text.truncate(500)}",
          title: category_info[:title],
          importance: category_info[:importance],
          confidence: 0.8,
          extraction_method: "auto_failure"
        )

        # High failure rate detection
        tasks_failed = metadata[:tasks_failed] || metadata["tasks_failed"]
        tasks_total = metadata[:tasks_total] || metadata["tasks_total"]
        if tasks_failed.to_i > 1 && tasks_total.to_i > 0
          rate = (tasks_failed.to_f / tasks_total * 100).round(1)
          if rate >= 50
            learnings << build_learning(
              category: "anti_pattern",
              content: "High failure rate: #{tasks_failed}/#{tasks_total} tasks failed (#{rate}%). Review team composition and task assignments.",
              title: "High failure rate detected",
              importance: 0.85,
              confidence: 0.8,
              extraction_method: "auto_failure"
            )
          end
        end

        learnings
      end

      # Extract learnings from a review
      def extract_from_review(review)
        learnings = []
        return learnings unless review.is_a?(Ai::TaskReview)

        # Rejection reason as anti-pattern
        if review.status == "rejected" && review.rejection_reason.present?
          learnings << build_learning(
            category: "anti_pattern",
            content: "Review rejected: #{review.rejection_reason.truncate(500)}",
            title: "Review rejection pattern",
            importance: 0.8,
            confidence: 0.85,
            extraction_method: "review"
          )
        end

        # Revision requests indicate areas for improvement
        if review.status == "revision_requested"
          learnings << build_learning(
            category: "review_finding",
            content: "Revision requested: #{review.rejection_reason || 'No specific reason given'}. Revision count: #{review.revision_count}",
            title: "Revision pattern",
            importance: 0.7,
            confidence: 0.75,
            extraction_method: "review"
          )
        end

        # Multiple revisions = anti-pattern
        if review.revision_count.to_i >= 2
          learnings << build_learning(
            category: "anti_pattern",
            content: "Task required #{review.revision_count} revisions before completion. Consider clearer task specifications or different agent assignment.",
            title: "Multi-revision anti-pattern",
            importance: 0.8,
            confidence: 0.8,
            extraction_method: "review"
          )
        end

        # Review findings from code review comments
        if review.respond_to?(:code_review_comments) && review.code_review_comments.any?
          review.code_review_comments.limit(5).each do |comment|
            learnings << build_learning(
              category: "review_finding",
              content: "Code review: #{comment.content.truncate(300)}",
              title: "Code review finding",
              importance: 0.65,
              confidence: 0.7,
              extraction_method: "review"
            )
          end
        end

        learnings
      end

      # Extract learnings from evaluation results
      def extract_from_evaluations(execution_id:)
        learnings = []

        results = Ai::EvaluationResult.where(execution_id: execution_id)
        return learnings if results.empty?

        results.each do |result|
          avg = result.average_score
          next unless avg

          if avg >= 4.0
            learnings << build_learning(
              category: "best_practice",
              content: "High evaluation score (#{avg}/5) for agent #{result.agent_id}. Scores: #{result.scores.to_json}",
              title: "High quality execution",
              importance: 0.7,
              confidence: 0.8,
              extraction_method: "evaluation",
              agent_id: result.agent_id
            )
          elsif avg <= 2.0
            learnings << build_learning(
              category: "anti_pattern",
              content: "Low evaluation score (#{avg}/5) for agent #{result.agent_id}. Scores: #{result.scores.to_json}",
              title: "Low quality execution",
              importance: 0.8,
              confidence: 0.8,
              extraction_method: "evaluation",
              agent_id: result.agent_id
            )
          end
        end

        learnings
      end

      private

      def classify_error(error_text)
        case error_text.downcase
        when /timeout|timed out|deadline/
          { label: "Timeout error", title: "Timeout failure", importance: 0.75 }
        when /rate.?limit|429|too many requests/
          { label: "Rate limit error", title: "Rate limit hit", importance: 0.7 }
        when /auth|unauthorized|403|401|forbidden/
          { label: "Authentication error", title: "Auth failure", importance: 0.8 }
        when /token.?limit|context.?length|max.?tokens/
          { label: "Token limit error", title: "Token limit exceeded", importance: 0.75 }
        when /connection|network|dns|socket/
          { label: "Network error", title: "Connection failure", importance: 0.65 }
        when /memory|oom|out of memory/
          { label: "Memory error", title: "Memory exhaustion", importance: 0.85 }
        else
          { label: "Execution error", title: "General failure", importance: 0.7 }
        end
      end

      def normalize_output(output)
        case output
        when String then output
        when Hash then output["text"] || output[:text] || output.to_json
        else output.to_s
        end
      end

      def build_learning(category:, content:, title:, importance:, confidence:, extraction_method:, agent_id: nil, skill_node_ids: nil)
        learning = {
          category: category,
          content: content,
          title: title,
          importance: importance,
          confidence: confidence,
          extraction_method: extraction_method,
          source_agent_id: agent_id
        }
        learning[:metadata] = { "skill_node_ids" => skill_node_ids } if skill_node_ids.present?
        learning
      end
    end
  end
end

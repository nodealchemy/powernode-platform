# frozen_string_literal: true

module Ai
  module Learning
    class EvaluationService
      def initialize(account:)
        @account = account
      end

      def evaluate_execution(execution:, output:, context: {})
        return unless Shared::FeatureFlagService.enabled?(:agent_evaluation)
        return unless execution.respond_to?(:agent) && execution.agent

        Thread.new do
          judge = Ai::Learning::LlmJudgeService.new(account: @account)
          scores = judge.evaluate(
            agent_output: output,
            task_description: context[:task_description] || execution.input_parameters&.dig("prompt"),
            expected_output: context[:expected_output]
          )

          Ai::EvaluationResult.create!(
            account: @account,
            agent: execution.agent,
            execution_id: execution.id,
            # evaluator_model is derived from the evaluator agent at call time
            # (no hardcoded default); it stays nil when no evaluator agent could
            # be resolved — record a sentinel so the presence validation does
            # not silently drop the (default-scored) result.
            evaluator_model: judge.evaluator_model || "unresolved",
            scores: scores[:scores],
            feedback: scores[:feedback]
          )
        rescue => e
          Rails.logger.error "[EvaluationService] Async evaluation failed: #{e.message}"
        end
      end

      def agent_score_trends(agent_id, period: 30.days)
        results = Ai::EvaluationResult.for_agent(agent_id)
                                       .in_time_range(period.ago)
                                       .order(:created_at)

        return {} if results.empty?

        {
          count: results.count,
          average_correctness: average_dimension(results, "correctness"),
          average_completeness: average_dimension(results, "completeness"),
          average_helpfulness: average_dimension(results, "helpfulness"),
          average_safety: average_dimension(results, "safety"),
          trend: calculate_trend(results)
        }
      end

      # Aggregate evaluation scores per skill node for an agent.
      #
      # ai_evaluation_results has no jsonb column suited to structured
      # attribution (only `scores`, which holds the four dimension numbers,
      # and `feedback`, which is free text) and `execution_id` carries no DB
      # foreign key, so it isn't locked to one execution model. In the
      # post_execution_extract flow, EvaluationResult#execution_id and
      # CompoundLearning#source_execution_id are populated from the same
      # team-execution id (see AutoExtractorService#extract_from_evaluations
      # and CompoundLearningService#store_learning), so attribution is
      # resolved by joining through that shared id rather than adding a
      # migration.
      def skill_performance_breakdown(agent_id:, period: 30.days)
        results = Ai::EvaluationResult.for_agent(agent_id)
                                       .in_time_range(period.ago)
                                       .to_a

        skill_ids_by_execution = skill_node_ids_by_execution(results.map(&:execution_id).compact.uniq)

        breakdown = {}

        results.each do |result|
          skill_ids = skill_ids_by_execution[result.execution_id] || legacy_feedback_skill_ids(result.feedback)
          next if skill_ids.blank?

          avg = result.average_score
          next unless avg

          skill_ids.uniq.each do |skill_id|
            breakdown[skill_id] ||= { scores: [], count: 0 }
            breakdown[skill_id][:scores] << avg
            breakdown[skill_id][:count] += 1
          end
        end

        breakdown.transform_values do |data|
          {
            average_score: (data[:scores].sum / data[:scores].size).round(2),
            evaluation_count: data[:count],
            min_score: data[:scores].min&.round(2),
            max_score: data[:scores].max&.round(2)
          }
        end
      rescue => e
        Rails.logger.warn "[EvaluationService] Skill performance breakdown failed: #{e.message}"
        {}
      end

      private

      def skill_node_ids_by_execution(execution_ids)
        return {} if execution_ids.blank?

        Ai::CompoundLearning
          .for_account(@account.id)
          .where(source_execution_id: execution_ids)
          .each_with_object({}) do |learning, memo|
            ids = Array(learning.metadata&.dig("skill_node_ids"))
            next if ids.blank?

            (memo[learning.source_execution_id] ||= []).concat(ids)
          end
      end

      # Legacy fallback only: historical writers may have serialized
      # structured feedback as a JSON string before attribution existed.
      # Plain free-text feedback (the normal case) must not raise or be
      # treated as an error.
      def legacy_feedback_skill_ids(feedback)
        return [] if feedback.blank?

        parsed = JSON.parse(feedback)
        return [] unless parsed.is_a?(Hash)

        Array(parsed["skill_node_ids"] || parsed.dig("metadata", "skill_node_ids"))
      rescue JSON::ParserError, TypeError
        []
      end

      def average_dimension(results, dimension)
        values = results.filter_map { |r| r.scores&.dig(dimension) }
        return nil if values.empty?

        (values.sum.to_f / values.size).round(2)
      end

      def calculate_trend(results)
        return "stable" if results.count < 5

        recent = results.last(5).filter_map(&:average_score)
        older = results.first(5).filter_map(&:average_score)

        return "stable" if recent.empty? || older.empty?

        recent_avg = recent.sum / recent.size
        older_avg = older.sum / older.size

        if recent_avg > older_avg + 0.3
          "improving"
        elsif recent_avg < older_avg - 0.3
          "declining"
        else
          "stable"
        end
      end
    end
  end
end

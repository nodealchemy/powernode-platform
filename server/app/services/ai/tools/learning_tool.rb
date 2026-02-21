# frozen_string_literal: true

module Ai
  module Tools
    class LearningTool < BaseTool
      REQUIRED_PERMISSION = "ai.agents.read"

      def self.definition
        {
          name: "compound_learning",
          description: "Query compound learnings, create new learnings, reinforce effective patterns, or get learning metrics",
          parameters: {
            action: { type: "string", required: true, description: "Action: query_learnings, reinforce_learning, learning_metrics, create_learning" },
            learning_id: { type: "string", required: false, description: "Learning ID (for reinforce)" },
            title: { type: "string", required: false, description: "Learning title (for create_learning)" },
            content: { type: "string", required: false, description: "Learning content (for create_learning)" },
            category: { type: "string", required: false, description: "Filter by category (pattern/anti_pattern/best_practice/discovery/fact/failure_mode/review_finding/performance_insight)" },
            scope: { type: "string", required: false, description: "Filter by scope (team/global)" },
            status: { type: "string", required: false, description: "Filter by status (active/superseded/archived)" },
            query: { type: "string", required: false, description: "Search query for learnings" },
            limit: { type: "integer", required: false, description: "Max results (default 20)" }
          }
        }
      end

      protected

      def call(params)
        case params[:action]
        when "query_learnings" then query_learnings(params)
        when "reinforce_learning" then reinforce_learning(params)
        when "learning_metrics" then learning_metrics
        when "create_learning" then create_learning(params)
        else { success: false, error: "Unknown action: #{params[:action]}. Valid actions: query_learnings, reinforce_learning, learning_metrics, create_learning" }
        end
      end

      private

      def query_learnings(params)
        scope = Ai::CompoundLearning.where(account: account)
        scope = scope.where(category: params[:category]) if params[:category].present?
        scope = scope.where(scope: params[:scope]) if params[:scope].present?
        scope = scope.where(status: params[:status] || "active")

        if params[:query].present?
          keywords = params[:query].downcase.split(/\s+/).first(5)
          keywords.each do |kw|
            sanitized = Ai::CompoundLearning.sanitize_sql_like(kw)
            scope = scope.where("LOWER(title) LIKE ? OR LOWER(content) LIKE ?", "%#{sanitized}%", "%#{sanitized}%")
          end
        end

        limit = (params[:limit] || 20).to_i.clamp(1, 50)
        learnings = scope.order(importance_score: :desc, created_at: :desc).limit(limit)

        {
          success: true,
          count: learnings.count,
          learnings: learnings.map { |l| serialize_learning(l) }
        }
      end

      def reinforce_learning(params)
        learning = Ai::CompoundLearning.find_by(id: params[:learning_id], account: account)
        return { success: false, error: "Learning not found" } unless learning

        learning.record_injection_outcome!(positive: true)
        learning.boost_importance!(0.05)

        { success: true, learning_id: learning.id, new_importance: learning.importance_score.to_f.round(4) }
      rescue StandardError => e
        { success: false, error: e.message }
      end

      def learning_metrics
        service = Ai::Learning::CompoundLearningService.new(account: account)
        metrics = service.compound_metrics

        {
          success: true,
          metrics: metrics
        }
      rescue StandardError => e
        { success: false, error: e.message }
      end

      def create_learning(params)
        return { success: false, error: "content is required" } if params[:content].blank?

        valid_categories = Ai::CompoundLearning::CATEGORIES
        category = params[:category].presence || "discovery"
        unless valid_categories.include?(category)
          return { success: false, error: "Invalid category: #{category}. Valid: #{valid_categories.join(', ')}" }
        end

        service = Ai::Learning::CompoundLearningService.new(account: account)
        stored = service.store_learning(
          {
            title: params[:title],
            content: params[:content],
            category: category,
            extraction_method: "manual",
            source_execution_successful: true,
            importance: 0.5,
            confidence: 0.5
          }
        )

        if stored
          { success: true, message: "Learning created successfully" }
        else
          { success: true, message: "Similar learning already exists and was reinforced" }
        end
      rescue StandardError => e
        { success: false, error: e.message }
      end

      def serialize_learning(learning)
        {
          id: learning.id,
          title: learning.title,
          content: learning.content.to_s.truncate(500),
          category: learning.category,
          scope: learning.scope,
          status: learning.status,
          importance_score: learning.importance_score.to_f.round(4),
          effectiveness_score: learning.effectiveness_score.to_f.round(4),
          injection_count: learning.injection_count,
          positive_outcomes: learning.positive_outcome_count,
          source_type: learning.extraction_method,
          created_at: learning.created_at&.iso8601
        }
      end
    end
  end
end

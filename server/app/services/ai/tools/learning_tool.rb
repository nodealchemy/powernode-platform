# frozen_string_literal: true

module Ai
  module Tools
    class LearningTool < BaseTool
      REQUIRED_PERMISSION = "ai.agents.read"

      # === Per-action permission gating (G4) ===
      #
      # This tool bundled WRITE and DESTRUCTIVE actions behind a single coarse
      # REQUIRED_PERMISSION of "ai.agents.read", and performed no check of its
      # own — so holding a READ permission was sufficient to run every one of
      # them. Proven by execution before the fix, with row oracles rather than
      # error strings.
      #
      # REST twin: LearningController gates `reinforce` and `promote` on
      # ai.analytics.manage and the read arms on ai.analytics.read
      # (learning_controller.rb:408-419).
      #
      # Keyed on the action that RUNS, never on the invoked NAME: a user
      # principal is deliberately not pinned to the tool name
      # (McpPlatformToolRegistrar#action_pinned_to_name?), so a name-keyed check
      # is bypassable by supplying a sibling :action.
      ACTION_PERMISSIONS = {
        "create_learning" => "ai.analytics.manage",
        "reinforce_learning" => "ai.analytics.manage"
      }.freeze


      # APO-1a (IMP-1e58753b3b6c) — governance declarations for every action
      # this tool advertises. NON-ENFORCING: `mutating:` alone leaves
      # BaseTool#gated_action? false, so #execute still routes to #call and
      # behaviour is unchanged. Gate wiring (categories/executors) is APO-1e.
      declare_action "create_learning", mutating: true
      declare_action "learning_metrics", mutating: false
      declare_action "query_learnings", mutating: false
      declare_action "reinforce_learning", mutating: true

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
            importance_score: { type: "number", required: false, description: "Importance score 0.0-1.0 (for create_learning, default: 0.5)" },
            confidence_score: { type: "number", required: false, description: "Confidence score 0.0-1.0 (for create_learning, default: 0.5)" },
            tags: { type: "array", required: false, description: "Tags array for categorization (for create_learning)" },
            scope: { type: "string", required: false, description: "Filter by scope (team/global)" },
            status: { type: "string", required: false, description: "Filter by status (active/superseded/archived)" },
            query: { type: "string", required: false, description: "Search query for learnings" },
            limit: { type: "integer", required: false, description: "Max results (default 20)" }
          }
        }
      end

      def self.action_definitions
        {
          "query_learnings" => {
            description: "Query compound learnings with optional filters and keyword search",
            parameters: {
              query: { type: "string", required: false, description: "Search query for learnings" },
              category: { type: "string", required: false, description: "Filter by category (pattern/anti_pattern/best_practice/discovery/fact/failure_mode/review_finding/performance_insight)" },
              scope: { type: "string", required: false, description: "Filter by scope (team/global)" },
              status: { type: "string", required: false, description: "Filter by status (active/superseded/archived)" },
              limit: { type: "integer", required: false, description: "Max results (default 20)" }
            }
          },
          "reinforce_learning" => {
            description: "Reinforce a compound learning by recording a positive outcome and boosting importance",
            parameters: {
              learning_id: { type: "string", required: true, description: "Learning ID to reinforce" }
            }
          },
          "learning_metrics" => {
            description: "Get compound learning metrics and effectiveness statistics",
            parameters: {}
          },
          "create_learning" => {
            description: "Create a new compound learning entry",
            parameters: {
              content: { type: "string", required: true, description: "Learning content" },
              title: { type: "string", required: false, description: "Learning title" },
              category: { type: "string", required: false, description: "Category (default: discovery)" },
              importance_score: { type: "number", required: false, description: "Importance score 0.0-1.0 (default: 0.5)" },
              confidence_score: { type: "number", required: false, description: "Confidence score 0.0-1.0 (default: 0.5)" },
              tags: { type: "array", required: false, description: "Tags array for categorization and dedup" }
            }
          }
        }
      end

      protected

      def call(params)
        action = params[:action].to_s

        unless action_permitted?(action)
          Rails.logger.warn(
            "[LearningTool] Refused action for insufficient permission: " \
            "action=#{action} requires=#{required_perm_for(action)} user=#{user&.id}"
          )
          return error_result("permission denied: #{required_perm_for(action)} required")
        end

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
        limit = (params[:limit] || 20).to_i.clamp(1, 50)

        # IMP-3470890a626f: a query routes through the service's embedding-first
        # retrieval (OR keyword fallback) — the old per-keyword .where chain
        # ANDed every word into the same row, so multi-word intent queries
        # returned nothing while each single word matched plenty. The no-query
        # form stays a plain filtered listing.
        if params[:query].present?
          learnings = ::Ai::Learning::CompoundLearningService.new(account: account).search_learnings(
            query: params[:query],
            category: params[:category],
            learning_scope: params[:scope],
            status: params[:status],
            limit: limit
          )
        else
          scope = Ai::CompoundLearning.where(account: account)
          scope = scope.where(category: params[:category]) if params[:category].present?
          scope = scope.where(scope: params[:scope]) if params[:scope].present?
          scope = scope.where(status: params[:status] || "active")
          learnings = scope.order(importance_score: :desc, created_at: :desc).limit(limit)
        end

        {
          success: true,
          count: learnings.size,
          learnings: learnings.map { |l| serialize_learning(l) }
        }
      end

      def reinforce_learning(params)
        learning = Ai::CompoundLearning.find_by(id: params[:learning_id], account: account)
        return { success: false, error: "Learning not found" } unless learning

        learning.record_injection_outcome!(successful: true)
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
            importance: (params[:importance_score] || 0.5).to_f.clamp(0.0, 1.0),
            confidence: (params[:confidence_score] || 0.5).to_f.clamp(0.0, 1.0),
            tags: Array(params[:tags])
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

      # Falls back to the class floor for read actions, which the registrar has
      # already enforced by the time this runs.
      def required_perm_for(action)
        ACTION_PERMISSIONS[action] || REQUIRED_PERMISSION
      end

      # Two explicit bypasses, matching the sibling tools' ladder: in-process
      # callers that opted in with `internal: true`, and an mTLS node principal
      # whose specific tool name already cleared Mcp::Principal#may_invoke?.
      # Never inferred from a nil user.
      def action_permitted?(action)
        return true if internal?
        return true if instance_authorized?
        return false unless user.respond_to?(:has_permission?)

        # Compared against true rather than used for truthiness: nothing on the
        # MCP path coerces a permission answer.
        user.has_permission?(required_perm_for(action)) == true
      end

    end
  end
end

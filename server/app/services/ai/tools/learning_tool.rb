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
      # ai.memory.write and the read arms on ai.analytics.read
      # (learning_controller.rb#validate_permissions, currently lines
      # 404-432 — the exact `when` clause moves as sibling actions are added,
      # so read the method rather than trusting a pinned line number).
      #
      # Keyed on the action that RUNS, never on the invoked NAME: a user
      # principal is deliberately not pinned to the tool name
      # (McpPlatformToolRegistrar#action_pinned_to_name?), so a name-keyed check
      # is bypassable by supplying a sibling :action.
      #
      # IMP-909ac33451cf / IMP-4d0550eac20e: both actions previously floored on
      # "ai.analytics.manage", a string Permissions.permission_exists? rejects
      # (absent from config/permissions.rb) — no seeded role could ever match
      # it, so the gate was reachable only via system.admin's blanket
      # short-circuit. Retargeted onto "ai.memory.write", the permission the
      # sibling G4 fix (SharedKnowledgeTool, same bundled-write defect) already
      # uses for this shape of write, and several real non-admin roles hold
      # (owner, manager, ai_specialist, system_worker), alongside admin.
      ACTION_PERMISSIONS = {
        "create_learning" => "ai.memory.write",
        "reinforce_learning" => "ai.memory.write",
        "retire_by_predicate" => "ai.memory.write",
        "hard_delete_retired" => "ai.memory.write"
      }.freeze


      # APO-1a (IMP-1e58753b3b6c) — governance declarations for every action
      # this tool advertises. NON-ENFORCING: `mutating:` alone leaves
      # BaseTool#gated_action? false, so #execute still routes to #call and
      # behaviour is unchanged. Gate wiring (categories/executors) is APO-1e.
      declare_action "create_learning", mutating: true
      declare_action "learning_metrics", mutating: false
      declare_action "query_learnings", mutating: false
      declare_action "reinforce_learning", mutating: true
      # IMP-3c9a6dc8f0a9 — dry_run: true is the caller's default too; see
      # Ai::Tools::SharedKnowledgeTool's identical note on its bulk actions.
      declare_action "retire_by_predicate", mutating: true, destructive: true
      declare_action "hard_delete_retired", mutating: true, destructive: true

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
            # Derived from the model constant so this cannot drift the way the
            # old hand-kept "active/superseded/archived" did — "archived" was
            # never a real status (see Ai::CompoundLearning::STATUSES), so a
            # caller filtering on it got a silently empty result forever.
            status: { type: "string", required: false, description: "Filter by status (#{Ai::CompoundLearning::STATUSES.join('/')})" },
            query: { type: "string", required: false, description: "Search query for learnings" },
            limit: { type: "integer", required: false, description: "Max results (default 20)" }
          }
        }
      end

      def self.action_definitions
        {
          "query_learnings" => {
            description: "Query compound learnings with optional filters. With a query, semantic search runs " \
                         "first and falls back to keyword search when it finds nothing or no embedding can be " \
                         "generated; match_mode says which ran (semantic | keyword | none, or filter when no " \
                         "query is given). That empty-result fallback is this recall verb's alone: learnings " \
                         "injected into agent context fall back to keywords only when no embedding can be generated.",
            parameters: {
              query: { type: "string", required: false, description: "Search query for learnings" },
              category: { type: "string", required: false, description: "Filter by category (pattern/anti_pattern/best_practice/discovery/fact/failure_mode/review_finding/performance_insight)" },
              scope: { type: "string", required: false, description: "Filter by scope (team/global)" },
              status: { type: "string", required: false, description: "Filter by status (#{Ai::CompoundLearning::STATUSES.join('/')})" },
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
          },
          "retire_by_predicate" => {
            description: "Predicate-scoped bulk retire (soft, reversible) of active/verified compound " \
                         "learnings — reaches untagged rows #reinforce_learning-style domain retirement " \
                         "cannot. dry_run defaults to true — returns the count and a first-3/last-1 sample " \
                         "without mutating; pass dry_run: false to actually retire. Refuses (does not " \
                         "truncate) if the predicate matches more than the per-call ceiling.",
            parameters: {
              status: { type: "string", required: false, description: "Filter by status (only active/verified are ever retired)" },
              category: { type: "string", required: false, description: "Filter by category" },
              scope: { type: "string", required: false, description: "Filter by scope (team/global)" },
              min_importance: { type: "number", required: false, description: "Filter: importance_score >=" },
              extraction_method: { type: "string", required: false, description: "Filter by extraction_method" },
              created_before: { type: "string", required: false, description: "Filter: created_at before this ISO8601 timestamp" },
              ids: { type: "array", required: false, description: "Filter: restrict to these learning ids" },
              reason: { type: "string", required: false, description: "Recorded on each retired row" },
              dry_run: { type: "boolean", required: false, description: "Default true — preview only, no mutation" }
            }
          },
          "hard_delete_retired" => {
            description: "Hard-delete (irreversible) compound learnings that are ALREADY retired or " \
                         "superseded. The predicate can only narrow this fixed base, never widen past it. " \
                         "dry_run defaults to true.",
            parameters: {
              category: { type: "string", required: false, description: "Filter by category" },
              scope: { type: "string", required: false, description: "Filter by scope (team/global)" },
              extraction_method: { type: "string", required: false, description: "Filter by extraction_method" },
              created_before: { type: "string", required: false, description: "Filter: created_at before this ISO8601 timestamp" },
              ids: { type: "array", required: false, description: "Filter: restrict to these learning ids" },
              dry_run: { type: "boolean", required: false, description: "Default true — preview only, no mutation" }
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
        when "retire_by_predicate" then retire_by_predicate(params)
        when "hard_delete_retired" then hard_delete_retired(params)
        else { success: false, error: "Unknown action: #{params[:action]}. Valid actions: query_learnings, reinforce_learning, learning_metrics, create_learning, retire_by_predicate, hard_delete_retired" }
        end
      end

      private

      def query_learnings(params)
        # Both retrieval branches below push an unrecognized status straight
        # into a .where(status: ...), which matches no row and returns
        # silently empty rather than erroring — the same failure shape that
        # let the "archived" advertisement bug go unnoticed. Refuse it here
        # instead, once, before either branch runs.
        if params[:status].present? && Ai::CompoundLearning::STATUSES.exclude?(params[:status])
          return { success: false, error: "Invalid status: #{params[:status]}. Valid: #{Ai::CompoundLearning::STATUSES.join(', ')}" }
        end

        limit = (params[:limit] || 20).to_i.clamp(1, 50)

        # IMP-3470890a626f: a query routes through the service's embedding-first
        # retrieval (OR keyword fallback) — the old per-keyword .where chain
        # ANDed every word into the same row, so multi-word intent queries
        # returned nothing while each single word matched plenty. The no-query
        # form stays a plain filtered listing.
        if params[:query].present?
          result = ::Ai::Learning::CompoundLearningService.new(account: account).search_learnings(
            query: params[:query],
            category: params[:category],
            learning_scope: params[:scope],
            status: params[:status],
            limit: limit
          )
          learnings = result[:learnings]
          # D7: name the branch that produced the rows so a caller reading zero
          # results can tell an empty corpus ("none") from a degraded embedding
          # path ("keyword") without server-side log access.
          match_mode = result[:match_mode]
        else
          scope = Ai::CompoundLearning.where(account: account)
          scope = scope.where(category: params[:category]) if params[:category].present?
          scope = scope.where(scope: params[:scope]) if params[:scope].present?
          scope = scope.where(status: params[:status] || "active")
          learnings = scope.order(importance_score: :desc, created_at: :desc).limit(limit)
          match_mode = "filter"
        end

        {
          success: true,
          count: learnings.size,
          match_mode: match_mode,
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
        rescued_error_result(e)
      end

      def learning_metrics
        service = Ai::Learning::CompoundLearningService.new(account: account)
        metrics = service.compound_metrics

        {
          success: true,
          metrics: metrics
        }
      rescue StandardError => e
        rescued_error_result(e)
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
        rescued_error_result(e)
      end

      # IMP-3c9a6dc8f0a9 — predicate-scoped bulk retire/hard-delete. Thin
      # wrappers: all dry-run/ceiling/audit behaviour lives in
      # Ai::Learning::CompoundLearningService, tested there. `dry_run`
      # defaults to true here too — only a literal `false` mutates.
      def retire_by_predicate(params)
        Ai::Learning::CompoundLearningService.new(account: account).retire_by_predicate!(
          predicate: bulk_learning_predicate_from(params),
          dry_run: params[:dry_run] != false,
          reason: params[:reason],
          actor: user
        )
      end

      def hard_delete_retired(params)
        Ai::Learning::CompoundLearningService.new(account: account).hard_delete_retired_or_superseded!(
          predicate: bulk_learning_predicate_from(params),
          dry_run: params[:dry_run] != false,
          actor: user
        )
      end

      def bulk_learning_predicate_from(params)
        {
          status: params[:status],
          category: params[:category],
          scope: params[:scope],
          min_importance: params[:min_importance],
          extraction_method: params[:extraction_method],
          created_before: params[:created_before],
          ids: Array(params[:ids]).presence
        }.compact
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

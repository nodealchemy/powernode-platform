# frozen_string_literal: true

module Ai
  module Ralph
    # The Ralph git tools as ONE governed tool (D2 review F3). It stays OFF the
    # MCP registry: a loop's git tools are reached only through a
    # Ai::Tools::LocalToolBinding built by TaskExecutor, which injects the loop
    # id server-side. Everything a registry tool gets, it gets, because it IS a
    # BaseTool run through the registry's guarded runner.
    #
    # Writes and deletes are declared approval-gated. Their categories are core
    # static categories with no seeded policy row, so
    # Ai::InterventionPolicyService resolves them to require_approval: a
    # delegated commit PARKS until an operator adds an InterventionPolicy row
    # for the category (operator ruling, D2 review F3 option (a)). Each write is
    # its own approval. On approval, Ai::Executors::DeferredToolCall replays the
    # call through this same #execute, which re-runs every guard except the gate.
    #
    # Reads are declared non-mutating and run directly.
    class RepositoryGitTool < ::Ai::Tools::BaseTool
      REQUIRED_PERMISSION = "ai.loops.execute"

      WRITE_CATEGORY = "ralph.repository_write"
      DELETE_CATEGORY = "ralph.repository_delete"

      READ_ACTIONS = %w[
        read_file list_files search_code get_file_info get_repo_info
        list_branches get_branch_diff list_commits
      ].freeze

      declare_action "write_file",
                     mutating: true,
                     action_category: WRITE_CATEGORY,
                     executor_class: "Ai::Executors::DeferredToolCall",
                     gate_context: :deferred_tool_call_context,
                     on_proceed: :deferred_tool_call_result
      declare_action "delete_file",
                     mutating: true,
                     destructive: true,
                     action_category: DELETE_CATEGORY,
                     executor_class: "Ai::Executors::DeferredToolCall",
                     gate_context: :deferred_tool_call_context,
                     on_proceed: :deferred_tool_call_result
      READ_ACTIONS.each { |name| declare_action name, mutating: false }

      def self.definition
        {
          name: "ralph_repository_git",
          description: "A Ralph loop's git tools, bound to the loop's own repository and branch",
          parameters: {
            type: "object",
            properties: {
              action: { type: "string", description: "The git tool to run" },
              ralph_loop_id: { type: "string", description: "Injected by the server; never model-supplied" }
            }
          }
        }
      end

      # Wraps the chokepoint only to RECORD a parked change on the run's ledger,
      # so an iteration with nothing committed says why. Every guard is
      # BaseTool#execute's.
      def execute(params:)
        result = super
        note_parked_change(params, result)
        result
      end

      private

      def call(params)
        action = routed_action_name(params)
        unless declared_git_action?(action)
          return error_result("Unknown git tool: #{action}")
        end

        executor = executor_for(params[:ralph_loop_id])
        return error_result("Ralph loop not found, or it has no repository of its own account") unless executor

        arguments = params.to_h.symbolize_keys.except(:action, :ralph_loop_id)
        result = executor.execute(action, arguments)
        result[:success] ? success_result(result.except(:success)) : error_result(result[:error])
      end

      def declared_git_action?(action)
        action.in?(READ_ACTIONS) || action.in?(%w[write_file delete_file])
      end

      # The run's own executor when this call belongs to a run in progress in
      # this process (a live call, or an auto-approved replay inside it), so the
      # run's ledger records the commit. A replay after a later approval has no
      # live run and builds its own, under the same tenancy and halt checks.
      def executor_for(loop_id)
        return nil if loop_id.blank?

        ralph_loop = account.ai_ralph_loops.find_by(id: loop_id)
        return nil unless ralph_loop

        live = GitToolExecutor.live_for(ralph_loop.id)
        return live if live
        return nil unless GitToolExecutor.available?(ralph_loop)

        GitToolExecutor.new(ralph_loop: ralph_loop)
      end

      def note_parked_change(params, result)
        return unless result.is_a?(Hash) && result.dig(:data, :pending)

        live = GitToolExecutor.live_for(params[:ralph_loop_id])
        live&.record_parked_change(params[:path], routed_action_name(params),
                                   result.dig(:data, :approval_request_id))
      end
    end
  end
end

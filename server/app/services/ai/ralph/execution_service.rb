# frozen_string_literal: true

module Ai
  module Ralph
    # ExecutionService - Orchestrates Ralph Loop execution
    #
    # Ralph Loops implement an iterative AI-driven development pattern:
    # 1. Parse PRD into discrete tasks
    # 2. Select next task based on priority and dependencies
    # 3. Execute task using configured AI tool (AMP/Claude Code)
    # 4. Validate results and extract learnings
    # 5. Repeat until all tasks completed or max iterations reached
    #
    class ExecutionService
      include LoopLifecycle
      include IterationExecution
      include PrdAndBroadcasting

      attr_reader :ralph_loop, :account, :user

      def initialize(ralph_loop:, account: nil, user: nil)
        @ralph_loop = ralph_loop
        @account = account || ralph_loop.account
        @user = user
      end

      # Code Factory integration - preflight gate check after task execution
      def code_factory_preflight_check(changed_files: [])
        return nil unless ralph_loop.code_factory_mode?

        service = ::Ai::CodeFactory::PreflightGateService.new(
          account: account,
          risk_contract: ralph_loop.risk_contract
        )

        service.evaluate(
          pr_number: ralph_loop.metadata&.dig("pr_number") || 0,
          head_sha: ralph_loop.metadata&.dig("head_sha") || "",
          changed_files: changed_files
        )
      rescue StandardError => e
        Rails.logger.warn("[Ralph::ExecutionService] Code Factory preflight check failed: #{e.message}")
        nil
      end

      # Code Factory integration - verify evidence requirements met
      def code_factory_evidence_satisfied?
        return true unless ralph_loop.code_factory_mode?
        return true unless ralph_loop.risk_contract

        review_state = account.ai_code_factory_review_states
          .where(risk_contract: ralph_loop.risk_contract)
          .where.not(status: "stale")
          .order(created_at: :desc)
          .first

        return true unless review_state
        return true unless review_state.evidence_required?

        review_state.evidence_verified?
      rescue StandardError => e
        Rails.logger.warn("[Ralph::ExecutionService] Code Factory evidence check failed: #{e.message}")
        true
      end

      private

      def success_result(data = {})
        { success: true }.merge(data)
      end

      def error_result(message, data = {})
        { success: false, error: message }.merge(data)
      end
    end
  end
end

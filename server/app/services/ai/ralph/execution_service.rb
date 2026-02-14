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

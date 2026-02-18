# frozen_string_literal: true

module Ai
  module Tools
    class RunnerDispatchTool < BaseTool
      REQUIRED_PERMISSION = "ai.workflows.execute"

      def self.definition
        {
          name: "dispatch_to_runner",
          description: "Dispatch a worktree execution to a self-hosted runner (GitHub Actions, Gitea Actions, or GitLab CI)",
          parameters: {
            session_id: { type: "string", required: true, description: "Worktree session ID" },
            worktree_id: { type: "string", required: true, description: "Worktree ID" },
            task_input: { type: "object", required: false, description: "Task input data" },
            runner_labels: { type: "array", required: false, description: "Required runner labels" }
          }
        }
      end

      protected

      def call(params)
        session = account.ai_worktree_sessions.find(params[:session_id])
        worktree = session.worktrees.find(params[:worktree_id])
        service = Ai::RunnerDispatchService.new(account: account, session: session)
        runner = service.select_runner(required_labels: params[:runner_labels] || [])
        return { success: false, error: "No available runner" } unless runner

        service.dispatch(worktree: worktree, task_input: params[:task_input] || {}, runner: runner)
      end
    end
  end
end

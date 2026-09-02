# frozen_string_literal: true

module Ai
  module Tools
    class RunnerDispatchTool < BaseTool
      REQUIRED_PERMISSION = "devops.ci.write"

      # APO-1a (IMP-1e58753b3b6c) — governance declarations for every action
      # this tool advertises. NON-ENFORCING: `mutating:` alone leaves
      # BaseTool#gated_action? false, so #execute still routes to #call and
      # behaviour is unchanged. Gate wiring (categories/executors) is APO-1e.
      declare_action "dispatch_to_runner", mutating: true

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
      rescue ActiveRecord::RecordNotFound => e
        { success: false, error: e.message }
      end
    end
  end
end

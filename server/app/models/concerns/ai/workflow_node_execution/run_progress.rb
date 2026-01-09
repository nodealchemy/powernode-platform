# frozen_string_literal: true

module Ai
  class WorkflowNodeExecution
    module RunProgress
      extend ActiveSupport::Concern

      def update_run_progress
        progress_key = "updating_run_progress_#{ai_workflow_run_id}"

        return if Thread.current[progress_key]

        Thread.current[progress_key] = true

        begin
          workflow_run.update_progress!
        ensure
          Thread.current[progress_key] = nil
        end
      end

      def add_cost_to_run_explicit(cost_amount)
        return unless cost_amount.present? && cost_amount > 0

        cost_key = "adding_cost_to_run_#{ai_workflow_run_id}"

        return if Thread.current[cost_key]

        Thread.current[cost_key] = true

        begin
          workflow_run.add_cost(cost_amount, "node_#{node_id}")
        ensure
          Thread.current[cost_key] = nil
        end
      end
    end
  end
end

# frozen_string_literal: true

module AiWorkflowRun::CostTracking
  extend ActiveSupport::Concern

  # Cost tracking
  def add_cost(amount, source = "node_execution")
    return unless amount.present? && amount > 0

    # CRITICAL FIX: Use thread-local storage for re-entry protection
    cost_key = "adding_workflow_cost_#{id}"

    return if Thread.current[cost_key]

    Thread.current[cost_key] = true

    begin
      increment!(:total_cost, amount)

      # Log cost addition
      ai_workflow_run_logs.create!(
        log_level: "info",
        event_type: "cost_added",
        message: "Added cost: $#{amount} from #{source}",
        context_data: {
          "amount" => amount,
          "source" => source,
          "total_cost" => total_cost + amount
        }
      )
    ensure
      Thread.current[cost_key] = nil
    end
  end

  def cost_breakdown
    node_costs = ai_workflow_node_executions.where("cost > 0").pluck(:node_id, :cost)

    {
      total_cost: total_cost,
      node_costs: node_costs.to_h,
      cost_per_node: node_costs.any? ? total_cost / node_costs.size : 0
    }
  end
end

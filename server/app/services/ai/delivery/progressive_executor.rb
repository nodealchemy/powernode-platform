# frozen_string_literal: true

module Ai
  module Delivery
    # Executes a PLANNED progressive delivery (canary | blue_green) by driving the corresponding
    # Devops::DeploymentStrategies strategy — which performs the staged weighted rollout (or
    # blue/green swap), health-checks between steps, and auto-rolls-back on failure — then records
    # the per-step results + final status onto the DeliveryRun. Invoked asynchronously (the
    # strategies pause between steps), so it is safe for it to block. Direct deliveries are a no-op
    # here (they run through Ai::Deploy in the orchestrator).
    class ProgressiveExecutor
      STRATEGY_CLASSES = {
        "canary" => "Devops::DeploymentStrategies::CanaryStrategy",
        "blue_green" => "Devops::DeploymentStrategies::BlueGreenStrategy"
      }.freeze
      SUCCESS_STATUSES = %i[completed succeeded].freeze
      ROLLED_BACK_STATUSES = %i[rolled_back].freeze

      def initialize(account:)
        @account = account
      end

      # Runs the strategy for a planned DeliveryRun and returns the (updated) run.
      def execute!(delivery_run)
        return delivery_run unless STRATEGY_CLASSES.key?(delivery_run.strategy)

        klass = STRATEGY_CLASSES[delivery_run.strategy].safe_constantize
        unless klass
          delivery_run.fail!("delivery strategy unavailable: #{delivery_run.strategy}")
          return delivery_run
        end

        delivery_run.update!(status: "running", started_at: delivery_run.started_at || Time.current)
        result = klass.new(account: @account).execute(
          config: strategy_config(delivery_run), context: strategy_context(delivery_run)
        )
        record_result!(delivery_run, result)
        delivery_run
      rescue StandardError => e
        delivery_run.fail!(e.message)
        delivery_run
      end

      private

      def strategy_config(run)
        cfg = (run.metadata["config"] || {}).deep_dup
        # The recorded canary plan is the authoritative step schedule.
        cfg["steps"] = run.steps if run.strategy == "canary" && run.steps.present?
        cfg
      end

      def strategy_context(run)
        { "ref" => run.ref, "base_ref" => run.base_ref, "delivery_run_id" => run.id, "environment" => run.environment }
      end

      def record_result!(run, result)
        status = (result[:status] || result["status"]).to_s.to_sym
        steps = result[:results] || result[:steps] || result["results"] || result["steps"] || run.steps

        if SUCCESS_STATUSES.include?(status)
          run.update!(status: "succeeded", steps: Array(steps), detail: "#{run.strategy} rollout complete", completed_at: Time.current)
        elsif ROLLED_BACK_STATUSES.include?(status)
          run.update!(status: "rolled_back", steps: Array(steps),
                      error_message: "auto-rolled back during #{run.strategy} rollout", completed_at: Time.current)
        else
          run.update!(status: "failed", steps: Array(steps),
                      error_message: "#{run.strategy} rollout #{status}", completed_at: Time.current)
        end
      end
    end
  end
end

# frozen_string_literal: true

module Ai
  module Delivery
    # Progressive-delivery orchestration on top of Ai::Deploy. Resolves the delivery strategy
    # for a target and dispatches:
    #   :direct      → Ai::Deploy::Orchestrator (single-shot deploy w/ migration-safety + health
    #                  + auto-rollback), linked to the DeliveryRun via deploy_run.
    #   :canary      → staged weighted rollout plan (reuses Devops::DeploymentStrategies::Canary
    #                  step schedule); step execution is driven separately.
    #   :blue_green  → deploy-inactive → health → swap plan (reuses BlueGreen strategy).
    # Records every delivery in an Ai::DeliveryRun. Dry-run by default (mirrors Ai::Deploy).
    class Orchestrator
      STRATEGIES = %i[direct canary blue_green].freeze

      def initialize(account:, user: nil, repository_path: nil)
        @account = account
        @user = user
        @repository_path = repository_path
      end

      def deliver(target:, ref:, base_ref: nil, campaign: nil, campaign_land: nil,
                  dry_run: true, allow_irreversible: false)
        strategy = resolve_strategy(target)
        run = @account.ai_delivery_runs.create!(
          campaign: campaign, campaign_land: campaign_land, repository: target.repository,
          triggered_by: @user, target_kind: target.kind.to_s, environment: target.environment,
          strategy: strategy.to_s, ref: ref, base_ref: base_ref, dry_run: dry_run, status: "pending"
        )
        run.start!

        case strategy
        when :direct
          deploy_run = Ai::Deploy::Orchestrator.new(account: @account, user: @user, repository_path: @repository_path)
                                               .deploy(target: target, ref: ref, base_ref: base_ref,
                                                       campaign: campaign, campaign_land: campaign_land,
                                                       dry_run: dry_run, allow_irreversible: allow_irreversible)
          run.attach_deploy_run!(deploy_run)
        when :canary, :blue_green
          run.plan!(progressive_plan(strategy, target))
        end

        run.reload
      rescue StandardError => e
        run&.fail!(e.message)
        raise
      end

      private

      def resolve_strategy(target)
        s = target.strategy
        STRATEGIES.include?(s) ? s : :direct
      end

      # The staged rollout plan for a progressive strategy. Reuses the canonical step schedules
      # from Devops::DeploymentStrategies so the plan matches what the executor will run.
      def progressive_plan(strategy, target)
        case strategy
        when :canary
          steps = target.config["steps"].presence ||
                  defined?(Devops::DeploymentStrategies::CanaryStrategy) && Devops::DeploymentStrategies::CanaryStrategy::DEFAULT_STEPS
          Array(steps).map.with_index { |step, i| { "phase" => "canary", "step" => i + 1 }.merge(step || {}) }
        when :blue_green
          [
            { "phase" => "deploy_inactive" },
            { "phase" => "health_check" },
            { "phase" => "swap_traffic" },
            { "phase" => "verify_active" }
          ]
        else
          []
        end
      end
    end
  end
end

# frozen_string_literal: true

module Ai
  module Tools
    # MCP surface for the progressive-delivery system (Ai::Delivery). Lets an agent / the
    # concierge deliver a ref to a target via a strategy (direct | canary | blue_green), and
    # inspect delivery runs. Thin wrapper over Ai::Delivery::Orchestrator, which composes with
    # Ai::Deploy (migration-safety + health + auto-rollback). DRY-RUN by default — a real
    # delivery requires an explicit dry_run: false.
    class DeliveryTool < BaseTool
      REQUIRED_PERMISSION = "git.pipelines.manage"

      # APO-1a (IMP-1e58753b3b6c) — governance declarations for every action
      # this tool advertises. NON-ENFORCING: `mutating:` alone leaves
      # BaseTool#gated_action? false, so #execute still routes to #call and
      # behaviour is unchanged. Gate wiring (categories/executors) is APO-1e.
      declare_action "deliver", mutating: true
      declare_action "delivery_list", mutating: false
      declare_action "delivery_status", mutating: false

      def self.definition
        {
          name: "delivery",
          description: "Progressive deployment delivery: deliver a ref to a target (platform-self or a " \
                       "project) via a strategy (direct | canary | blue_green), and inspect deliveries. " \
                       "Dry-run by default; pass dry_run:false for a real delivery.",
          parameters: {
            action: { type: "string", required: true,
                      description: "deliver | delivery_status | delivery_list" },
            target_kind: { type: "string", required: false, description: "platform_self | project (default project)" },
            repository_id: { type: "string", required: false, description: "Devops::GitRepository UUID (project deliveries)" },
            environment: { type: "string", required: false, description: "Target environment (default production)" },
            strategy: { type: "string", required: false, description: "direct | canary | blue_green (default direct)" },
            ref: { type: "string", required: false, description: "Git ref/SHA to deliver" },
            base_ref: { type: "string", required: false, description: "Previously-delivered ref (migration-safety + rollback)" },
            config: { type: "object", required: false, description: "Method/strategy overrides (e.g. steps, cluster_id, image)" },
            dry_run: { type: "boolean", required: false, description: "Describe without mutating (default true)" },
            delivery_id: { type: "string", required: false, description: "DeliveryRun UUID (delivery_status)" },
            limit: { type: "integer", required: false, description: "Max rows (delivery_list, default 50)" }
          }
        }
      end

      def self.action_definitions
        {
          "deliver" => {
            description: "Deliver a ref to a target via a strategy. direct delegates to Ai::Deploy " \
                         "(migration-safety + health + auto-rollback); canary/blue_green record the staged " \
                         "rollout plan. DRY-RUN by default — pass dry_run:false for a real delivery.",
            parameters: {
              target_kind: { type: "string", required: false, description: "platform_self | project (default project)" },
              repository_id: { type: "string", required: false, description: "Devops::GitRepository UUID (project)" },
              environment: { type: "string", required: false, description: "Target environment (default production)" },
              strategy: { type: "string", required: false, description: "direct | canary | blue_green (default direct)" },
              ref: { type: "string", required: false, description: "Git ref/SHA to deliver" },
              base_ref: { type: "string", required: false, description: "Previously-delivered ref" },
              config: { type: "object", required: false, description: "Method/strategy overrides" },
              dry_run: { type: "boolean", required: false, description: "Describe without mutating (default true)" }
            }
          },
          "delivery_status" => {
            description: "Get a delivery run's status (strategy, phase/steps, underlying deploy run).",
            parameters: { delivery_id: { type: "string", required: true, description: "DeliveryRun UUID" } }
          },
          "delivery_list" => {
            description: "List this account's recent delivery runs (newest first).",
            parameters: { limit: { type: "integer", required: false, description: "Max rows (default 50)" } }
          }
        }
      end

      protected

      def call(params)
        case params[:action]
        when "deliver" then deliver(params)
        when "delivery_status" then delivery_status(params)
        when "delivery_list" then delivery_list(params)
        else error_result("Unknown action: #{params[:action]}")
        end
      end

      private

      def halted?
        account.respond_to?(:ai_suspended?) && account.ai_suspended?
      end

      def deliver(params)
        return success_result(halted: true) if halted?

        target = Ai::Delivery::TargetBuilder.from_params(
          account: account, target_kind: params[:target_kind], repository_id: params[:repository_id],
          environment: params[:environment], strategy: params[:strategy], config: params[:config]
        )
        run = Ai::Delivery::Orchestrator.new(account: account, user: user).deliver(
          target: target, ref: params[:ref], base_ref: params[:base_ref],
          dry_run: params.key?(:dry_run) ? ActiveModel::Type::Boolean.new.cast(params[:dry_run]) : true
        )
        success_result(delivery: run.summary)
      rescue ArgumentError, ActiveRecord::RecordInvalid => e
        error_result(e.message)
      end

      def delivery_status(params)
        run = account.ai_delivery_runs.find_by(id: params[:delivery_id])
        return error_result("Delivery run not found") unless run

        success_result(delivery: run.summary)
      end

      def delivery_list(params)
        runs = account.ai_delivery_runs.recent(params[:limit].presence&.to_i || 50)
        success_result(deliveries: runs.map(&:summary))
      end
    end
  end
end

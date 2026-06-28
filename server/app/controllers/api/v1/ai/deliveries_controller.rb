# frozen_string_literal: true

module Api
  module V1
    module Ai
      # Human/frontend surface for the progressive-delivery system (Ai::Delivery). Trigger a
      # delivery (direct | canary | blue_green) and list/inspect delivery runs. Reuses the same
      # TargetBuilder + Orchestrator as the MCP DeliveryTool. Dry-run by default — a real delivery
      # requires dry_run:false.
      class DeliveriesController < ApplicationController
        before_action :require_manage
        before_action :reject_if_ai_suspended, only: %i[create]

        def index
          scope = current_user.account.ai_delivery_runs
          total = scope.count
          render_success(deliveries: scope.recent(params.fetch(:limit, 50).to_i).map(&:summary), total_count: total)
        end

        def show
          render_success(current_user.account.ai_delivery_runs.find(params[:id]).summary)
        end

        def create
          target = ::Ai::Delivery::TargetBuilder.from_params(
            account: current_user.account, target_kind: params[:target_kind],
            repository_id: params[:repository_id], environment: params[:environment],
            strategy: params[:strategy], config: permitted_hash(:config)
          )
          run = ::Ai::Delivery::Orchestrator.new(account: current_user.account, user: current_user).deliver(
            target: target, ref: params[:ref], base_ref: params[:base_ref],
            dry_run: params.key?(:dry_run) ? ActiveModel::Type::Boolean.new.cast(params[:dry_run]) : true
          )
          render_success(run.summary, status: :created)
        rescue ArgumentError, ActiveRecord::RecordInvalid => e
          render_error(e.message, status: :unprocessable_content)
        end

        private

        def require_manage
          require_permission("git.pipelines.manage")
        end

        def reject_if_ai_suspended
          return unless current_user.account.ai_suspended?

          render_error("AI activity is suspended for this account", status: :conflict)
        end

        def permitted_hash(key)
          raw = params[key]
          return {} if raw.blank?
          return raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)

          raw.is_a?(Hash) ? raw : {}
        end
      end
    end
  end
end

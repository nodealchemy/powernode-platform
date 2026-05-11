# frozen_string_literal: true

module Api
  module V1
    module Ai
      # CRUD for `Ai::ApprovalChain` records, used by the autonomy framework's
      # multi-step approval flow. A chain assigns ordered steps with typed
      # approver specs (permission/role/user) and an optional timeout/timeout
      # action. Chains are referenced from `Ai::InterventionPolicy` rows so
      # operators can wire per-action approval workflows from the Settings UI.
      class ApprovalChainsController < ApplicationController
        before_action :require_chain_management_permission
        before_action :set_chain, only: %i[show update destroy]

        # GET /api/v1/ai/approval_chains
        def index
          chains = ::Ai::ApprovalChain.where(account_id: current_account.id).order(name: :asc)
          render_success(data: chains.map { |c| serialize(c) })
        end

        # GET /api/v1/ai/approval_chains/:id
        def show
          render_success(data: serialize(@chain, detailed: true))
        end

        # POST /api/v1/ai/approval_chains
        def create
          chain = ::Ai::ApprovalChain.new(chain_params.merge(account: current_account, created_by: current_user))
          chain.trigger_type ||= "autonomy_action"
          chain.status ||= "active"

          if chain.save
            render_success(data: serialize(chain.reload, detailed: true), status: :created)
          else
            render_validation_error(chain)
          end
        end

        # PATCH /api/v1/ai/approval_chains/:id
        def update
          if @chain.update(chain_params)
            render_success(data: serialize(@chain.reload, detailed: true))
          else
            render_validation_error(@chain)
          end
        end

        # DELETE /api/v1/ai/approval_chains/:id
        # Soft-delete: sets status to "disabled". Hard-delete blocked when any
        # request still references the chain (the `dependent: :destroy` on the
        # association would cascade-destroy in-flight requests, which we
        # explicitly want to prevent).
        def destroy
          if @chain.approval_requests.where(status: "pending").exists?
            return render_error(
              "Cannot delete chain with pending approval requests",
              status: :unprocessable_content
            )
          end

          @chain.update!(status: "disabled")
          render_success(data: serialize(@chain.reload))
        end

        private

        def require_chain_management_permission
          require_permission("ai.approval_chains.manage")
        end

        def set_chain
          @chain = ::Ai::ApprovalChain.where(account_id: current_account.id).find(params[:id])
        end

        def chain_params
          permitted = params.require(:approval_chain).permit(
            :name, :description, :is_sequential, :timeout_hours, :timeout_action,
            :status, :trigger_type
          )
          # `steps` is a JSONB array of nested hashes — strong params doesn't
          # cleanly handle deeply-nested heterogeneous shapes, so accept the
          # raw structure here and rely on `Ai::ApprovalChain#validate_steps_shape`
          # for sanitization.
          if params[:approval_chain].key?(:steps)
            raw_steps = params[:approval_chain][:steps]
            raw_steps = raw_steps.to_unsafe_h if raw_steps.respond_to?(:to_unsafe_h)
            raw_steps = raw_steps.values if raw_steps.is_a?(Hash)
            permitted[:steps] = Array(raw_steps).map do |s|
              s = s.to_unsafe_h if s.respond_to?(:to_unsafe_h)
              s.deep_stringify_keys
            end
          end
          permitted
        end

        def serialize(chain, detailed: false)
          base = {
            id: chain.id,
            name: chain.name,
            description: chain.description,
            trigger_type: chain.trigger_type,
            status: chain.status,
            is_sequential: chain.is_sequential,
            timeout_hours: chain.timeout_hours,
            timeout_action: chain.timeout_action,
            step_count: chain.step_count,
            usage_count: chain.usage_count,
            created_at: chain.created_at,
            updated_at: chain.updated_at
          }
          return base unless detailed

          base.merge(
            steps: chain.steps,
            pending_request_count: chain.approval_requests.where(status: "pending").count
          )
        end
      end
    end
  end
end

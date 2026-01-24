# frozen_string_literal: true

module Api
  module V1
    module SupplyChain
      class RemediationPlansController < BaseController
        before_action :require_read_permission, only: [:index, :show]
        before_action :require_write_permission, only: [:create, :update, :destroy, :generate_pr, :execute]
        before_action :require_admin_permission, only: [:approve, :reject]
        before_action :set_remediation_plan, only: [:show, :update, :destroy, :generate_pr, :approve, :reject, :execute]

        # GET /api/v1/supply_chain/remediation_plans
        def index
          @plans = current_account.supply_chain_remediation_plans
                                  .includes(:vulnerability, :created_by, :approved_by)
                                  .order(created_at: :desc)

          @plans = @plans.where(status: params[:status]) if params[:status].present?
          @plans = @plans.where(priority: params[:priority]) if params[:priority].present?

          @plans = paginate(@plans)

          render_success(
            { remediation_plans: @plans.map { |p| serialize_plan(p) } },
            meta: pagination_meta
          )
        end

        # GET /api/v1/supply_chain/remediation_plans/:id
        def show
          render_success({ remediation_plan: serialize_plan(@plan, include_details: true) })
        end

        # POST /api/v1/supply_chain/remediation_plans
        def create
          @plan = current_account.supply_chain_remediation_plans.build(plan_params)
          @plan.created_by = current_user
          @plan.status = "draft"

          if @plan.save
            render_success({ remediation_plan: serialize_plan(@plan) }, status: :created)
          else
            render_error(@plan.errors.full_messages.join(", "), status: :unprocessable_entity)
          end
        end

        # PATCH/PUT /api/v1/supply_chain/remediation_plans/:id
        def update
          unless @plan.editable?
            return render_error("Plan cannot be edited in current status", status: :unprocessable_entity)
          end

          if @plan.update(plan_params)
            render_success({ remediation_plan: serialize_plan(@plan) })
          else
            render_error(@plan.errors.full_messages.join(", "), status: :unprocessable_entity)
          end
        end

        # DELETE /api/v1/supply_chain/remediation_plans/:id
        def destroy
          unless @plan.deletable?
            return render_error("Plan cannot be deleted in current status", status: :unprocessable_entity)
          end

          @plan.destroy
          render_success(message: "Remediation plan deleted")
        end

        # POST /api/v1/supply_chain/remediation_plans/:id/generate_pr
        def generate_pr
          unless @plan.approved?
            return render_error("Plan must be approved before generating PR", status: :unprocessable_entity)
          end

          result = ::SupplyChain::RemediationService.generate_pull_request(@plan, current_user)

          if result[:success]
            @plan.update!(
              status: "pr_generated",
              pr_url: result[:pr_url],
              pr_number: result[:pr_number]
            )

            render_success(
              { remediation_plan: serialize_plan(@plan), pr_url: result[:pr_url] },
              message: "Pull request generated successfully"
            )
          else
            render_error(result[:error], status: :unprocessable_entity)
          end
        end

        # POST /api/v1/supply_chain/remediation_plans/:id/approve
        def approve
          unless @plan.pending_approval?
            return render_error("Plan is not pending approval", status: :unprocessable_entity)
          end

          @plan.approve!(current_user, params[:comment])

          SupplyChainChannel.broadcast_to_account(
            current_account,
            type: "remediation_plan_approved",
            plan_id: @plan.id,
            approved_by: current_user.id,
            timestamp: Time.current.iso8601
          )

          render_success(
            { remediation_plan: serialize_plan(@plan) },
            message: "Remediation plan approved"
          )
        end

        # POST /api/v1/supply_chain/remediation_plans/:id/reject
        def reject
          unless @plan.pending_approval?
            return render_error("Plan is not pending approval", status: :unprocessable_entity)
          end

          if params[:reason].blank?
            return render_error("Rejection reason is required", status: :unprocessable_entity)
          end

          @plan.reject!(current_user, params[:reason])

          render_success(
            { remediation_plan: serialize_plan(@plan) },
            message: "Remediation plan rejected"
          )
        end

        # POST /api/v1/supply_chain/remediation_plans/:id/execute
        def execute
          unless @plan.approved? || @plan.pr_generated?
            return render_error("Plan must be approved before execution", status: :unprocessable_entity)
          end

          @plan.update!(status: "executing", execution_started_at: Time.current)

          # Queue the execution job
          ::SupplyChain::RemediationExecutionJob.perform_later(@plan.id, current_user.id)

          render_success(
            { remediation_plan: serialize_plan(@plan) },
            message: "Remediation execution started"
          )
        end

        private

        def set_remediation_plan
          @plan = current_account.supply_chain_remediation_plans.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Remediation plan not found", status: :not_found)
        end

        def plan_params
          params.require(:remediation_plan).permit(
            :title, :description, :priority, :vulnerability_id,
            :target_version, :remediation_type, :deadline,
            steps: [], affected_components: [], metadata: {}
          )
        end

        def serialize_plan(plan, include_details: false)
          data = {
            id: plan.id,
            title: plan.title,
            description: plan.description,
            status: plan.status,
            priority: plan.priority,
            remediation_type: plan.remediation_type,
            target_version: plan.target_version,
            deadline: plan.deadline,
            vulnerability_id: plan.vulnerability_id,
            vulnerability_cve: plan.vulnerability&.cve_id,
            created_by: plan.created_by ? {
              id: plan.created_by.id,
              name: plan.created_by.name
            } : nil,
            created_at: plan.created_at,
            updated_at: plan.updated_at
          }

          if include_details
            data[:steps] = plan.steps
            data[:affected_components] = plan.affected_components
            data[:pr_url] = plan.pr_url
            data[:pr_number] = plan.pr_number
            data[:approved_by] = plan.approved_by ? {
              id: plan.approved_by.id,
              name: plan.approved_by.name
            } : nil
            data[:approved_at] = plan.approved_at
            data[:rejection_reason] = plan.rejection_reason
            data[:execution_started_at] = plan.execution_started_at
            data[:execution_completed_at] = plan.execution_completed_at
            data[:metadata] = plan.metadata
          end

          data
        end
      end
    end
  end
end

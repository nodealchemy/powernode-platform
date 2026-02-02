# frozen_string_literal: true

module Api
  module V1
    module SupplyChain
      class RemediationPlansController < BaseController
        before_action :require_read_permission, only: [ :index, :show ]
        before_action :require_write_permission, only: [ :create, :update, :destroy, :execute, :generate_pr ]
        before_action :require_admin_permission, only: [ :approve, :reject ]
        before_action :set_remediation_plan, only: [ :show, :update, :destroy, :approve, :reject, :execute, :generate_pr ]

        # GET /api/v1/supply_chain/remediation_plans
        def index
          @plans = current_account.supply_chain_remediation_plans
                                  .includes(:sbom, :created_by, :approved_by)
                                  .order(created_at: :desc)

          @plans = @plans.where(status: params[:status]) if params[:status].present?
          @plans = @plans.where(plan_type: params[:plan_type]) if params[:plan_type].present?

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
            render_error(@plan.errors.full_messages.join(", "), status: :unprocessable_content)
          end
        end

        # PATCH/PUT /api/v1/supply_chain/remediation_plans/:id
        def update
          unless @plan.draft?
            return render_error("Plan cannot be edited in current status", status: :unprocessable_content)
          end

          if @plan.update(plan_params)
            render_success({ remediation_plan: serialize_plan(@plan) })
          else
            render_error(@plan.errors.full_messages.join(", "), status: :unprocessable_content)
          end
        end

        # DELETE /api/v1/supply_chain/remediation_plans/:id
        def destroy
          unless @plan.draft?
            return render_error("Plan cannot be deleted in current status", status: :unprocessable_content)
          end

          @plan.destroy
          render_success(message: "Remediation plan deleted")
        end

        # POST /api/v1/supply_chain/remediation_plans/:id/approve
        def approve
          unless @plan.pending_review?
            return render_error("Plan is not pending approval", status: :unprocessable_content)
          end

          @plan.approve!(current_user)

          render_success(
            { remediation_plan: serialize_plan(@plan) },
            message: "Remediation plan approved"
          )
        end

        # POST /api/v1/supply_chain/remediation_plans/:id/reject
        def reject
          unless @plan.pending_review?
            return render_error("Plan is not pending approval", status: :unprocessable_content)
          end

          if params[:reason].blank?
            return render_error("Rejection reason is required", status: :unprocessable_content)
          end

          @plan.reject!(current_user, params[:reason])

          render_success(
            { remediation_plan: serialize_plan(@plan) },
            message: "Remediation plan rejected"
          )
        end

        # POST /api/v1/supply_chain/remediation_plans/:id/execute
        def execute
          unless @plan.approved?
            return render_error("Plan must be approved before execution", status: :unprocessable_content)
          end

          @plan.start_execution!

          render_success(
            { remediation_plan: serialize_plan(@plan) },
            message: "Remediation execution started"
          )
        end

        # POST /api/v1/supply_chain/remediation_plans/:id/generate_pr
        def generate_pr
          unless @plan.approved?
            return render_error("Plan must be approved before generating a PR", status: :unprocessable_content)
          end

          if @plan.generated_pr_url.present?
            return render_error("PR has already been generated for this plan", status: :unprocessable_content)
          end

          repository = find_repository_for_plan
          unless repository
            return render_error("No repository associated with this remediation plan", status: :unprocessable_content)
          end

          service = ::SupplyChain::RemediationPrService.new(
            plan: @plan,
            repository: repository,
            user: current_user
          )

          result = service.generate_pr

          if result[:success]
            render_success(
              {
                remediation_plan: serialize_plan(@plan.reload, include_details: true),
                pr_url: result[:pr_url],
                pr_number: result[:pr_number],
                branch_name: result[:branch_name]
              },
              message: "Pull request created successfully"
            )
          else
            render_error(result[:error], status: :unprocessable_content)
          end
        rescue ArgumentError => e
          render_error(e.message, status: :unprocessable_content)
        end

        private

        def find_repository_for_plan
          # Try to find repository via SBOM -> container image -> repository chain
          # or via explicit repository_id in plan metadata
          if @plan.metadata&.dig("repository_id")
            return current_account.devops_repositories.find_by(id: @plan.metadata["repository_id"])
          end

          # Try to find via SBOM association
          if @plan.sbom&.metadata&.dig("repository_id")
            return current_account.devops_repositories.find_by(id: @plan.sbom.metadata["repository_id"])
          end

          # Default to first repository if only one exists (common for smaller projects)
          repos = current_account.devops_repositories
          repos.count == 1 ? repos.first : nil
        end

        def set_remediation_plan
          @plan = current_account.supply_chain_remediation_plans.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Remediation plan not found", status: :not_found)
        end

        def plan_params
          params.require(:remediation_plan).permit(
            :plan_type, :sbom_id, :auto_executable, :confidence_score,
            :generated_pr_url,
            target_vulnerabilities: [], upgrade_recommendations: [],
            breaking_changes: [], metadata: {}
          )
        end

        def serialize_plan(plan, include_details: false)
          data = {
            id: plan.id,
            plan_type: plan.plan_type,
            status: plan.status,
            approval_status: plan.approval_status,
            confidence_score: plan.confidence_score,
            auto_executable: plan.auto_executable,
            target_vulnerability_count: plan.target_vulnerability_count,
            upgrade_count: plan.upgrade_count,
            has_breaking_changes: plan.has_breaking_changes?,
            sbom_id: plan.sbom_id,
            created_by: plan.created_by ? {
              id: plan.created_by.id,
              name: plan.created_by.name
            } : nil,
            created_at: plan.created_at,
            updated_at: plan.updated_at
          }

          if include_details
            data[:target_vulnerabilities] = plan.target_vulnerabilities
            data[:upgrade_recommendations] = plan.upgrade_recommendations
            data[:breaking_changes] = plan.breaking_changes
            data[:generated_pr_url] = plan.generated_pr_url
            data[:approved_by] = plan.approved_by ? {
              id: plan.approved_by.id,
              name: plan.approved_by.name
            } : nil
            data[:approved_at] = plan.approved_at
            data[:metadata] = plan.metadata
          end

          data
        end
      end
    end
  end
end

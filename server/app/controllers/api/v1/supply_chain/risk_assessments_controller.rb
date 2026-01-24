# frozen_string_literal: true

module Api
  module V1
    module SupplyChain
      class RiskAssessmentsController < BaseController
        before_action :require_read_permission, only: [:index, :show]
        before_action :require_write_permission, only: [:create]
        before_action :require_admin_permission, only: [:approve, :reject]
        before_action :set_vendor
        before_action :set_assessment, only: [:show, :approve, :reject]

        # GET /api/v1/supply_chain/vendors/:vendor_id/assessments
        def index
          @assessments = @vendor.risk_assessments
                                .includes(:assessed_by, :approved_by)
                                .order(created_at: :desc)

          @assessments = @assessments.where(status: params[:status]) if params[:status].present?
          @assessments = @assessments.where(assessment_type: params[:type]) if params[:type].present?

          @assessments = paginate(@assessments)

          render_success(
            { risk_assessments: @assessments.map { |a| serialize_assessment(a) } },
            meta: pagination_meta
          )
        end

        # GET /api/v1/supply_chain/vendors/:vendor_id/assessments/:id
        def show
          render_success({ risk_assessment: serialize_assessment(@assessment, include_details: true) })
        end

        # POST /api/v1/supply_chain/vendors/:vendor_id/assessments
        def create
          @assessment = @vendor.risk_assessments.build(assessment_params)
          @assessment.account = current_account
          @assessment.assessed_by = current_user
          @assessment.status = "pending"

          if @assessment.save
            # Calculate scores
            @assessment.calculate_scores!

            SupplyChainChannel.broadcast_vendor_assessment_completed(@assessment)

            render_success({ risk_assessment: serialize_assessment(@assessment) }, status: :created)
          else
            render_error(@assessment.errors.full_messages.join(", "), status: :unprocessable_entity)
          end
        end

        # POST /api/v1/supply_chain/vendors/:vendor_id/assessments/:id/approve
        def approve
          unless @assessment.pending?
            return render_error("Assessment is not pending approval", status: :unprocessable_entity)
          end

          @assessment.approve!(current_user, params[:comment])

          # Update vendor risk profile
          @vendor.update_risk_profile_from_assessment(@assessment)

          render_success(
            { risk_assessment: serialize_assessment(@assessment) },
            message: "Risk assessment approved"
          )
        end

        # POST /api/v1/supply_chain/vendors/:vendor_id/assessments/:id/reject
        def reject
          unless @assessment.pending?
            return render_error("Assessment is not pending approval", status: :unprocessable_entity)
          end

          if params[:reason].blank?
            return render_error("Rejection reason is required", status: :unprocessable_entity)
          end

          @assessment.reject!(current_user, params[:reason])

          render_success(
            { risk_assessment: serialize_assessment(@assessment) },
            message: "Risk assessment rejected"
          )
        end

        private

        def set_vendor
          @vendor = current_account.supply_chain_vendors.find(params[:vendor_id])
        rescue ActiveRecord::RecordNotFound
          render_error("Vendor not found", status: :not_found)
        end

        def set_assessment
          @assessment = @vendor.risk_assessments.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Risk assessment not found", status: :not_found)
        end

        def assessment_params
          params.require(:risk_assessment).permit(
            :assessment_type, :assessment_date,
            :security_score, :compliance_score, :operational_score,
            :financial_score, :reputation_score,
            :overall_risk_level, :notes, :valid_until,
            findings: [], recommendations: [], controls_evaluated: [], metadata: {}
          )
        end

        def serialize_assessment(assessment, include_details: false)
          data = {
            id: assessment.id,
            assessment_id: assessment.assessment_id,
            assessment_type: assessment.assessment_type,
            status: assessment.status,
            assessment_date: assessment.assessment_date,
            security_score: assessment.security_score,
            compliance_score: assessment.compliance_score,
            operational_score: assessment.operational_score,
            financial_score: assessment.financial_score,
            reputation_score: assessment.reputation_score,
            overall_score: assessment.overall_score,
            overall_risk_level: assessment.overall_risk_level,
            valid_until: assessment.valid_until,
            assessed_by: assessment.assessed_by ? {
              id: assessment.assessed_by.id,
              name: assessment.assessed_by.name
            } : nil,
            vendor_id: assessment.vendor_id,
            created_at: assessment.created_at
          }

          if include_details
            data[:findings] = assessment.findings
            data[:recommendations] = assessment.recommendations
            data[:controls_evaluated] = assessment.controls_evaluated
            data[:notes] = assessment.notes
            data[:approved_by] = assessment.approved_by ? {
              id: assessment.approved_by.id,
              name: assessment.approved_by.name
            } : nil
            data[:approved_at] = assessment.approved_at
            data[:rejection_reason] = assessment.rejection_reason
            data[:metadata] = assessment.metadata
          end

          data
        end
      end
    end
  end
end

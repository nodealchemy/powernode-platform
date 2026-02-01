# frozen_string_literal: true

module Api
  module V1
    module SupplyChain
      class RiskAssessmentsController < BaseController
        before_action :require_read_permission, only: [:index, :show]
        before_action :require_write_permission, only: [:create]
        before_action :require_admin_permission, only: [:submit_for_review, :complete]
        before_action :set_vendor
        before_action :set_assessment, only: [:show, :submit_for_review, :complete]

        # GET /api/v1/supply_chain/vendors/:vendor_id/assessments
        def index
          @assessments = @vendor.risk_assessments
                                .includes(:assessor)
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
          @assessment.assessor = current_user
          @assessment.status = "draft"

          if @assessment.save
            render_success({ risk_assessment: serialize_assessment(@assessment) }, status: :created)
          else
            render_error(@assessment.errors.full_messages.join(", "), status: :unprocessable_content)
          end
        end

        # POST /api/v1/supply_chain/vendors/:vendor_id/assessments/:id/submit_for_review
        def submit_for_review
          unless @assessment.draft? || @assessment.in_progress?
            return render_error("Assessment cannot be submitted for review in current status", status: :unprocessable_content)
          end

          @assessment.submit_for_review!

          render_success(
            { risk_assessment: serialize_assessment(@assessment) },
            message: "Risk assessment submitted for review"
          )
        end

        # POST /api/v1/supply_chain/vendors/:vendor_id/assessments/:id/complete
        def complete
          unless @assessment.pending_review?
            return render_error("Assessment is not pending review", status: :unprocessable_content)
          end

          valid_months = params[:valid_months]&.to_i || 12
          @assessment.complete!(valid_months)

          render_success(
            { risk_assessment: serialize_assessment(@assessment) },
            message: "Risk assessment completed"
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
            :valid_until,
            findings: [], recommendations: [], evidence: [], metadata: {}
          )
        end

        def serialize_assessment(assessment, include_details: false)
          data = {
            id: assessment.id,
            assessment_type: assessment.assessment_type,
            status: assessment.status,
            assessment_date: assessment.assessment_date,
            security_score: assessment.security_score,
            compliance_score: assessment.compliance_score,
            operational_score: assessment.operational_score,
            overall_score: assessment.overall_score,
            risk_level: assessment.risk_level,
            valid_until: assessment.valid_until,
            assessor: assessment.assessor ? {
              id: assessment.assessor.id,
              name: assessment.assessor.name
            } : nil,
            vendor_id: assessment.vendor_id,
            created_at: assessment.created_at
          }

          if include_details
            data[:findings] = assessment.findings
            data[:recommendations] = assessment.recommendations
            data[:evidence] = assessment.evidence
            data[:completed_at] = assessment.completed_at
            data[:metadata] = assessment.metadata
          end

          data
        end
      end
    end
  end
end

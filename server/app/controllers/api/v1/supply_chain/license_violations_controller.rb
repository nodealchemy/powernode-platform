# frozen_string_literal: true

module Api
  module V1
    module SupplyChain
      class LicenseViolationsController < BaseController
        before_action :require_read_permission, only: [ :index, :show, :statistics ]
        before_action :require_write_permission, only: [ :update, :resolve, :request_exception ]
        before_action :require_admin_permission, only: [ :approve_exception, :reject_exception ]
        before_action :set_violation, only: [ :show, :update, :resolve, :request_exception, :approve_exception, :reject_exception ]

        # GET /api/v1/supply_chain/license_violations
        def index
          @violations = current_account.supply_chain_license_violations
                                       .includes(:license, :license_policy, :sbom_component)
                                       .order(created_at: :desc)

          # Filters
          @violations = @violations.where(status: params[:status]) if params[:status].present?
          @violations = @violations.where(severity: params[:severity]) if params[:severity].present?
          @violations = @violations.where(violation_type: params[:violation_type]) if params[:violation_type].present?
          @violations = @violations.where(license_policy_id: params[:policy_id]) if params[:policy_id].present?

          @violations = paginate(@violations)

          render_success(
            { license_violations: @violations.map { |v| serialize_violation(v) } },
            meta: pagination_meta
          )
        end

        # GET /api/v1/supply_chain/license_violations/:id
        def show
          render_success({ license_violation: serialize_violation(@violation, include_details: true) })
        end

        # PATCH/PUT /api/v1/supply_chain/license_violations/:id
        def update
          if @violation.update(violation_update_params)
            render_success({ license_violation: serialize_violation(@violation) })
          else
            render_error(@violation.errors.full_messages.join(", "), status: :unprocessable_content)
          end
        end

        # POST /api/v1/supply_chain/license_violations/:id/resolve
        def resolve
          resolution = params[:resolution] || "resolved"
          notes = params[:notes]

          @violation.resolve!(resolution: resolution, notes: notes, resolved_by: current_user)

          render_success({
            message: "Violation resolved",
            license_violation: serialize_violation(@violation)
          })
        rescue StandardError => e
          render_error("Failed to resolve: #{e.message}", status: :unprocessable_content)
        end

        # POST /api/v1/supply_chain/license_violations/:id/request_exception
        def request_exception
          justification = params[:justification]
          expires_at = params[:expires_at]

          if justification.blank?
            render_error("Justification is required for exception request", status: :unprocessable_content)
            return
          end

          @violation.request_exception!(
            justification: justification,
            expires_at: expires_at,
            requested_by: current_user
          )

          render_success({
            message: "Exception requested",
            license_violation: serialize_violation(@violation)
          })
        rescue StandardError => e
          render_error("Failed to request exception: #{e.message}", status: :unprocessable_content)
        end

        # POST /api/v1/supply_chain/license_violations/:id/approve_exception
        def approve_exception
          notes = params[:notes]
          expires_at = params[:expires_at] || @violation.exception_expires_at

          @violation.approve_exception!(
            approved_by: current_user,
            notes: notes,
            expires_at: expires_at
          )

          render_success({
            message: "Exception approved",
            license_violation: serialize_violation(@violation)
          })
        rescue StandardError => e
          render_error("Failed to approve exception: #{e.message}", status: :unprocessable_content)
        end

        # POST /api/v1/supply_chain/license_violations/:id/reject_exception
        def reject_exception
          reason = params[:reason]

          @violation.reject_exception!(rejected_by: current_user, reason: reason)

          render_success({
            message: "Exception rejected",
            license_violation: serialize_violation(@violation)
          })
        rescue StandardError => e
          render_error("Failed to reject exception: #{e.message}", status: :unprocessable_content)
        end

        # GET /api/v1/supply_chain/license_violations/statistics
        def statistics
          violations = current_account.supply_chain_license_violations

          render_success({
            total: violations.count,
            by_status: violations.group(:status).count,
            by_severity: violations.group(:severity).count,
            by_type: violations.group(:violation_type).count,
            open_count: violations.where(status: "open").count,
            exception_pending: violations.where(exception_requested: true, exception_status: "pending").count
          })
        end

        private

        def set_violation
          @violation = current_account.supply_chain_license_violations.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("License violation not found", status: :not_found)
        end

        def violation_update_params
          params.require(:license_violation).permit(:notes, metadata: {})
        end

        def serialize_violation(violation, include_details: false)
          data = {
            id: violation.id,
            status: violation.status,
            severity: violation.severity,
            violation_type: violation.violation_type,
            component_name: violation.sbom_component&.name,
            component_version: violation.sbom_component&.version,
            license_spdx_id: violation.license&.spdx_id,
            license_name: violation.license&.name,
            policy_name: violation.license_policy&.name,
            notes: violation.notes,
            created_at: violation.created_at
          }

          if include_details
            data[:description] = violation.description
            data[:recommendation] = violation.recommendation
            data[:notes] = violation.notes
            data[:resolved_at] = violation.resolved_at
            data[:resolved_by_id] = violation.resolved_by_id
            data[:exception_justification] = violation.exception_justification
            data[:exception_expires_at] = violation.exception_expires_at
            data[:exception_approved_by_id] = violation.exception_approved_by_id
            data[:ai_remediation] = violation.ai_remediation
            data[:metadata] = violation.metadata
          end

          data
        end
      end
    end
  end
end

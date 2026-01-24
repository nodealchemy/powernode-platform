# frozen_string_literal: true

module Api
  module V1
    module SupplyChain
      class LicenseDetectionsController < BaseController
        before_action :require_read_permission, only: [:index, :show]
        before_action :require_write_permission, only: [:override]
        before_action :set_detection, only: [:show, :override]

        # GET /api/v1/supply_chain/license_detections
        def index
          @detections = current_account.supply_chain_license_detections
                                       .includes(:component, :license, :detected_in)
                                       .order(created_at: :desc)

          @detections = @detections.where(detection_method: params[:method]) if params[:method].present?
          @detections = @detections.where(confidence_level: params[:confidence]) if params[:confidence].present?
          @detections = @detections.where(overridden: true) if params[:overridden] == "true"
          @detections = @detections.where(overridden: false) if params[:overridden] == "false"

          if params[:license_id].present?
            @detections = @detections.where(license_id: params[:license_id])
          end

          if params[:component_id].present?
            @detections = @detections.where(component_id: params[:component_id])
          end

          @detections = paginate(@detections)

          render_success(
            { license_detections: @detections.map { |d| serialize_detection(d) } },
            meta: pagination_meta
          )
        end

        # GET /api/v1/supply_chain/license_detections/:id
        def show
          render_success({ license_detection: serialize_detection(@detection, include_details: true) })
        end

        # POST /api/v1/supply_chain/license_detections/:id/override
        def override
          if params[:license_id].blank?
            return render_error("license_id is required for override", status: :unprocessable_entity)
          end

          new_license = ::SupplyChain::License.find(params[:license_id])

          @detection.update!(
            overridden: true,
            override_license_id: new_license.id,
            override_reason: params[:reason],
            overridden_by: current_user,
            overridden_at: Time.current
          )

          audit_log(
            action: "license_detection_override",
            resource: @detection,
            details: {
              original_license_id: @detection.license_id,
              new_license_id: new_license.id,
              reason: params[:reason]
            }
          )

          render_success(
            { license_detection: serialize_detection(@detection) },
            message: "License detection overridden"
          )
        rescue ActiveRecord::RecordNotFound
          render_error("License not found", status: :not_found)
        end

        private

        def set_detection
          @detection = current_account.supply_chain_license_detections.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("License detection not found", status: :not_found)
        end

        def serialize_detection(detection, include_details: false)
          effective_license = detection.overridden? ? detection.override_license : detection.license

          data = {
            id: detection.id,
            detection_id: detection.detection_id,
            detection_method: detection.detection_method,
            confidence_level: detection.confidence_level,
            confidence_score: detection.confidence_score,
            component: detection.component ? {
              id: detection.component.id,
              name: detection.component.name,
              version: detection.component.version
            } : nil,
            detected_license: detection.license ? {
              id: detection.license.id,
              spdx_id: detection.license.spdx_id,
              name: detection.license.name,
              category: detection.license.category
            } : nil,
            effective_license: effective_license ? {
              id: effective_license.id,
              spdx_id: effective_license.spdx_id,
              name: effective_license.name,
              category: effective_license.category
            } : nil,
            overridden: detection.overridden,
            detected_in_type: detection.detected_in_type,
            detected_in_id: detection.detected_in_id,
            created_at: detection.created_at
          }

          if include_details
            data[:source_file] = detection.source_file
            data[:source_line] = detection.source_line
            data[:match_text] = detection.match_text
            data[:override_reason] = detection.override_reason
            data[:overridden_by] = detection.overridden_by ? {
              id: detection.overridden_by.id,
              name: detection.overridden_by.name
            } : nil
            data[:overridden_at] = detection.overridden_at
            data[:metadata] = detection.metadata
          end

          data
        end
      end
    end
  end
end

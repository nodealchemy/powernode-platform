# frozen_string_literal: true

module Api
  module V1
    module SupplyChain
      class LicenseDetectionsController < BaseController
        before_action :require_read_permission, only: [ :index, :show ]
        before_action :require_write_permission, only: [ :mark_review ]
        before_action :set_detection, only: [ :show, :mark_review ]

        # GET /api/v1/supply_chain/license_detections
        def index
          @detections = current_account.supply_chain_license_detections
                                       .includes(:sbom_component, :license)
                                       .order(created_at: :desc)

          @detections = @detections.where(detection_source: params[:source]) if params[:source].present?
          @detections = @detections.where(requires_review: true) if params[:requires_review] == "true"
          @detections = @detections.where(requires_review: false) if params[:requires_review] == "false"
          @detections = @detections.where(is_primary: true) if params[:primary] == "true"

          if params[:license_id].present?
            @detections = @detections.where(license_id: params[:license_id])
          end

          if params[:sbom_component_id].present?
            @detections = @detections.where(sbom_component_id: params[:sbom_component_id])
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

        # POST /api/v1/supply_chain/license_detections/:id/mark_review
        def mark_review
          reason = params[:reason]

          @detection.mark_needs_review!(reason)

          render_success(
            { license_detection: serialize_detection(@detection) },
            message: "License detection marked for review"
          )
        end

        private

        def set_detection
          @detection = current_account.supply_chain_license_detections.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("License detection not found", status: :not_found)
        end

        def serialize_detection(detection, include_details: false)
          data = {
            id: detection.id,
            detected_license_id: detection.detected_license_id,
            detected_license_name: detection.detected_license_name,
            detection_source: detection.detection_source,
            confidence_score: detection.confidence_score,
            is_primary: detection.is_primary,
            requires_review: detection.requires_review,
            sbom_component: detection.sbom_component ? {
              id: detection.sbom_component.id,
              name: detection.sbom_component.respond_to?(:full_name) ? detection.sbom_component.full_name : detection.sbom_component.name,
              version: detection.sbom_component.version
            } : nil,
            license: detection.license ? {
              id: detection.license.id,
              spdx_id: detection.license.spdx_id,
              name: detection.license.name
            } : nil,
            effective_license_id: detection.effective_license_id,
            effective_license_name: detection.effective_license_name,
            created_at: detection.created_at
          }

          if include_details
            data[:file_path] = detection.file_path
            data[:ai_interpretation] = detection.ai_interpretation
            data[:metadata] = detection.metadata
          end

          data
        end
      end
    end
  end
end

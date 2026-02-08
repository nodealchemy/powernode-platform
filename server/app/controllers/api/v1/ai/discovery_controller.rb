# frozen_string_literal: true

module Api
  module V1
    module Ai
      class DiscoveryController < ApplicationController
        before_action :authenticate_request
        before_action :authorize_read!, only: %i[index show]
        before_action :authorize_manage!, only: %i[scan recommend]

        # GET /api/v1/ai/discovery
        def index
          results = current_account.ai_discovery_results.recent.limit(20)
          results = results.by_type(params[:scan_type]) if params[:scan_type].present?

          render_success(results.map(&:scan_summary))
        end

        # GET /api/v1/ai/discovery/:id
        def show
          result = current_account.ai_discovery_results.find(params[:id])
          render_success(result.as_json)
        rescue ActiveRecord::RecordNotFound
          render_not_found("Discovery Result")
        end

        # POST /api/v1/ai/discovery/scan
        def scan
          scan_type = params[:scan_type] || "full_scan"

          result = current_account.ai_discovery_results.create!(
            scan_type: scan_type,
            status: "pending"
          )

          # Queue worker job for background scanning
          ::Ai::DiscoveryScanJob.perform_async(
            account_id: current_account.id,
            scan_type: scan_type,
            scan_id: result.scan_id
          )

          render_success(result.scan_summary, status: :accepted)
        rescue ActiveRecord::RecordInvalid => e
          render_validation_error(e.record.errors)
        end

        # POST /api/v1/ai/discovery/recommend
        def recommend
          task_description = params[:task_description]
          return render_error("Task description required", status: :bad_request) if task_description.blank?

          service = ::Ai::Discovery::TaskAnalyzerService.new(account: current_account)
          recommendations = service.analyze(task_description)

          render_success(recommendations)
        end

        private

        def authorize_read!
          return if current_user.has_permission?("ai.discovery.read")

          render_forbidden
        end

        def authorize_manage!
          return if current_user.has_permission?("ai.discovery.manage")

          render_forbidden
        end
      end
    end
  end
end

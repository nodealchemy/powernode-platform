# frozen_string_literal: true

module Api
  module V1
    module Ai
      module Intelligence
        class SupplyChainsController < ApplicationController
          include EnterpriseFeatureGate
          require_enterprise_feature "intelligence"
          before_action :validate_permissions

          # POST /api/v1/ai/intelligence/supply_chain/analyze
          def analyze
            result = if params[:sbom_id].present?
                       service.triage_vulnerabilities(sbom_id: params[:sbom_id])
                     else
                       service.security_posture
                     end

            render_success(data: result)
          rescue StandardError => e
            render_error(e.message, status: :unprocessable_content)
          end

          # GET /api/v1/ai/intelligence/supply_chain/risk_summary
          def risk_summary
            result = service.analyze_risk_trends(
              period_days: params[:period_days]&.to_i || 30
            )

            render_success(data: result)
          rescue StandardError => e
            render_error(e.message, status: :unprocessable_content)
          end

          # GET /api/v1/ai/intelligence/supply_chain/vulnerability_report
          def vulnerability_report
            result = service.security_posture(
              sbom_id: params[:sbom_id]
            )

            render_success(data: result)
          rescue StandardError => e
            render_error(e.message, status: :unprocessable_content)
          end

          private

          def validate_permissions
            return if current_worker || current_service

            require_permission("ai.intelligence.view")
          end

          def service
            @service ||= ::Ai::Intelligence::SupplyChainAnalysisService.new(account: current_account)
          end
        end
      end
    end
  end
end

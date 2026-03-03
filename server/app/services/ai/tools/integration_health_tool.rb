# frozen_string_literal: true

module Ai
  module Tools
    class IntegrationHealthTool < BaseTool
      REQUIRED_PERMISSION = nil # Accessible to all agents

      def self.definition
        {
          name: "integration_health",
          description: "Check the health status of integrations for the current account. " \
                       "Returns status, last check time, and failure count for each integration instance.",
          parameters: {
            integration_type: { type: "string", required: false, description: "Filter by integration type (e.g., 'gitea', 'github', 'slack')" },
            health_status: { type: "string", required: false, description: "Filter by health status: 'healthy', 'degraded', 'unhealthy', 'unknown'" }
          }
        }
      end

      def self.action_definitions
        { "integration_health" => definition }
      end

      protected

      def call(params)
        scope = ::Devops::IntegrationInstance.where(account: account).includes(:template)

        if params[:integration_type].present?
          scope = scope.joins(:template)
                       .where(devops_integration_templates: { integration_type: params[:integration_type] })
        end

        scope = scope.where(health_status: params[:health_status]) if params[:health_status].present?

        integrations = scope.map do |instance|
          {
            id: instance.id,
            name: instance.name,
            type: instance.template_type,
            status: instance.status,
            health_status: instance.health_status,
            last_health_check_at: instance.last_health_check_at,
            consecutive_failures: instance.consecutive_failures,
            last_error: instance.last_error,
            success_rate: instance.success_rate
          }
        end

        {
          success: true,
          integrations: integrations,
          summary: {
            total: integrations.size,
            healthy: integrations.count { |i| i[:health_status] == "healthy" },
            degraded: integrations.count { |i| i[:health_status] == "degraded" },
            unhealthy: integrations.count { |i| i[:health_status] == "unhealthy" },
            unknown: integrations.count { |i| i[:health_status] == "unknown" || i[:health_status].nil? }
          }
        }
      rescue StandardError => e
        { success: false, error: "Integration health check failed: #{e.message}" }
      end
    end
  end
end

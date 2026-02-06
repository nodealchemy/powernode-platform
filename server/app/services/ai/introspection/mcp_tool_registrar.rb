# frozen_string_literal: true

module Ai
  module Introspection
    class McpToolRegistrar
      INTROSPECTION_TOOLS = [
        {
          id: "platform.health",
          name: "platform_health",
          description: "Overall platform health score and component breakdown",
          category: "introspection",
          permission_level: "read",
          required_permissions: ["ai.introspection.view"],
          input_schema: {
            type: "object",
            properties: {},
            required: []
          }
        },
        {
          id: "platform.metrics",
          name: "platform_metrics",
          description: "System overview: workflows, executions, performance, costs",
          category: "introspection",
          permission_level: "read",
          required_permissions: ["ai.introspection.view"],
          input_schema: {
            type: "object",
            properties: {
              time_range_minutes: { type: "integer", default: 60, description: "Time range in minutes" }
            },
            required: []
          }
        },
        {
          id: "platform.provider_health",
          name: "platform_provider_health",
          description: "Per-provider success rate, latency, and circuit breaker state",
          category: "introspection",
          permission_level: "read",
          required_permissions: ["ai.introspection.view"],
          input_schema: {
            type: "object",
            properties: {
              time_range_minutes: { type: "integer", default: 60 }
            },
            required: []
          }
        },
        {
          id: "platform.alerts",
          name: "platform_alerts",
          description: "Active alerts and circuit breaker states",
          category: "introspection",
          permission_level: "read",
          required_permissions: ["ai.introspection.view"],
          input_schema: {
            type: "object",
            properties: {},
            required: []
          }
        },
        {
          id: "platform.infrastructure",
          name: "platform_infrastructure",
          description: "DB, Redis, worker, and connectivity health",
          category: "introspection",
          permission_level: "read",
          required_permissions: ["ai.introspection.view"],
          input_schema: {
            type: "object",
            properties: {
              skip_cache: { type: "boolean", default: false }
            },
            required: []
          }
        },
        {
          id: "platform.cost_analysis",
          name: "platform_cost_analysis",
          description: "Cost breakdown by provider and time period",
          category: "introspection",
          permission_level: "read",
          required_permissions: ["ai.introspection.view"],
          input_schema: {
            type: "object",
            properties: {
              time_range_minutes: { type: "integer", default: 60 }
            },
            required: []
          }
        },
        {
          id: "platform.recent_events",
          name: "platform_recent_events",
          description: "Unified cross-system execution events",
          category: "introspection",
          permission_level: "read",
          required_permissions: ["ai.introspection.view"],
          input_schema: {
            type: "object",
            properties: {
              source_type: { type: "string", description: "Filter by source type" },
              status: { type: "string", description: "Filter by status" },
              limit: { type: "integer", default: 50 }
            },
            required: []
          }
        },
        {
          id: "platform.resources",
          name: "platform_resources",
          description: "List available agents, workflows, pipelines, and teams",
          category: "introspection",
          permission_level: "read",
          required_permissions: ["ai.introspection.view"],
          input_schema: {
            type: "object",
            properties: {
              resource_type: { type: "string", enum: %w[agents workflows pipelines teams] }
            },
            required: ["resource_type"]
          }
        },
        {
          id: "platform.config",
          name: "platform_config",
          description: "Get configuration for a specific resource",
          category: "introspection",
          permission_level: "read",
          required_permissions: ["ai.introspection.view"],
          input_schema: {
            type: "object",
            properties: {
              resource_type: { type: "string" },
              resource_id: { type: "string" }
            },
            required: %w[resource_type resource_id]
          }
        }
      ].freeze

      class << self
        def register_all!(account:)
          registry = Mcp::RegistryService.new(account: account)

          INTROSPECTION_TOOLS.each do |tool_def|
            manifest = build_manifest(tool_def)

            begin
              registry.register_tool(tool_def[:id], manifest)
            rescue => e
              Rails.logger.warn "[McpToolRegistrar] Failed to register #{tool_def[:id]}: #{e.message}"
            end
          end
        end

        def execute_tool(tool_id, params:, account:, agent_id: nil)
          if agent_id
            Ai::Introspection::RateLimiter.check!(agent_id: agent_id)
          end

          return nil unless Shared::FeatureFlagService.enabled?(:agent_introspection)

          case tool_id
          when "platform.health"
            metrics_service(account).system_health
          when "platform.metrics"
            time_range = (params[:time_range_minutes] || 60).minutes
            metrics_service(account).system_overview(time_range)
          when "platform.provider_health"
            time_range = (params[:time_range_minutes] || 60).minutes
            metrics_service(account).provider_metrics(time_range)
          when "platform.alerts"
            metrics_service(account).active_alerts
          when "platform.infrastructure"
            health_service(account).comprehensive_health_check(
              skip_cache: params[:skip_cache] || false
            )
          when "platform.cost_analysis"
            time_range = (params[:time_range_minutes] || 60).minutes
            metrics_service(account).cost_analysis(time_range)
          when "platform.recent_events"
            introspection_service(account).recent_events(
              source_type: params[:source_type],
              status: params[:status],
              limit: params[:limit] || 50
            )
          when "platform.resources"
            introspection_service(account).list_resources(
              type: params[:resource_type]
            )
          when "platform.config"
            introspection_service(account).get_resource_config(
              type: params[:resource_type],
              id: params[:resource_id]
            )
          end
        end

        private

        def build_manifest(tool_def)
          {
            name: tool_def[:name],
            description: tool_def[:description],
            category: tool_def[:category],
            version: "1.0.0",
            permission_level: tool_def[:permission_level],
            required_permissions: tool_def[:required_permissions],
            input_schema: tool_def[:input_schema],
            rate_limited: true,
            rate_limit: { max_calls: 10, window_seconds: 60 }
          }
        end

        def metrics_service(account)
          Ai::AiOpsMetricsService.new(account: account)
        end

        def health_service(account)
          Ai::MonitoringHealthService.new(account: account)
        end

        def introspection_service(account)
          Ai::Introspection::PlatformIntrospectionService.new(account: account)
        end
      end
    end
  end
end

# frozen_string_literal: true

# MCP Hosting Service - Managed MCP server operations
#
# Handles all MCP hosting operations:
# - Server creation and deployment
# - Server lifecycle management
# - Deployment management
# - Metrics collection
# - Marketplace operations
#
module Mcp
  class HostingService
    attr_reader :account, :errors

    def initialize(account)
      @account = account
      @errors = []
    end

    # ==========================================================================
    # SERVER MANAGEMENT
    # ==========================================================================

    def list_servers(status: nil, visibility: nil, limit: 50, offset: 0)
      scope = Mcp::HostedServer
        .where(account: account)
        .order(created_at: :desc)
        .offset(offset)
        .limit(limit)

      scope = scope.where(status: status) if status.present?
      scope = scope.where(visibility: visibility) if visibility.present?

      {
        servers: scope.map(&:summary),
        total_count: scope.except(:limit, :offset).count,
        limit: limit,
        offset: offset
      }
    end

    def get_server(server_id)
      server = find_server(server_id)
      return nil unless server

      server.detailed_summary
    end

    def create_server(params)
      server = Mcp::HostedServer.create!(
        account: account,
        name: params[:name],
        description: params[:description],
        server_type: params[:server_type] || "custom",
        source_type: params[:source_type] || "git",
        source_url: params[:source_url],
        source_branch: params[:source_branch] || "main",
        source_path: params[:source_path],
        entry_point: params[:entry_point] || "index.js",
        runtime: params[:runtime] || "node18",
        environment_variables: params[:environment_variables] || {},
        resource_limits: params[:resource_limits] || default_resource_limits,
        capabilities: params[:capabilities] || [],
        tool_manifest: params[:tool_manifest] || {},
        visibility: params[:visibility] || "private",
        status: "pending"
      )

      server.summary
    rescue ActiveRecord::RecordInvalid => e
      @errors << e.message
      nil
    end

    def update_server(server_id, params)
      server = find_server(server_id)
      return nil unless server

      server.update!(params.slice(
        :name, :description, :source_url, :source_branch, :source_path,
        :entry_point, :runtime, :environment_variables, :resource_limits,
        :capabilities, :tool_manifest, :visibility
      ))

      server.reload.summary
    rescue ActiveRecord::RecordInvalid => e
      @errors << e.message
      nil
    end

    def delete_server(server_id)
      server = find_server(server_id)
      return nil unless server

      server.soft_delete!
      { success: true, server_id: server_id }
    rescue StandardError => e
      @errors << e.message
      nil
    end

    # ==========================================================================
    # DEPLOYMENT MANAGEMENT
    # ==========================================================================

    def deploy_server(server_id, version: nil, commit_sha: nil, user: nil)
      server = find_server(server_id)
      return nil unless server

      unless server.can_deploy?
        @errors << "Server cannot be deployed in current state"
        return nil
      end

      deployment = server.deployments.create!(
        version: version || generate_version(server),
        commit_sha: commit_sha,
        status: "pending",
        deployed_by: user,
        configuration_snapshot: {
          runtime: server.runtime,
          entry_point: server.entry_point,
          environment_variables: server.environment_variables.keys,
          resource_limits: server.resource_limits
        }
      )

      # Queue the actual deployment job
      # McpServerDeployJob.perform_async(deployment.id)

      server.update!(status: "building")

      {
        deployment: deployment.summary,
        server: server.reload.summary
      }
    rescue ActiveRecord::RecordInvalid => e
      @errors << e.message
      nil
    end

    def rollback_deployment(server_id, deployment_id: nil)
      server = find_server(server_id)
      return nil unless server

      target_deployment = if deployment_id
        server.deployments.find(deployment_id)
      else
        server.deployments.where(status: "running").order(created_at: :desc).second
      end

      unless target_deployment
        @errors << "No deployment to rollback to"
        return nil
      end

      current = server.current_deployment
      current&.update!(status: "rolled_back")

      new_deployment = server.deployments.create!(
        version: "#{target_deployment.version}-rollback",
        commit_sha: target_deployment.commit_sha,
        status: "deploying",
        configuration_snapshot: target_deployment.configuration_snapshot,
        rollback_from_id: current&.id
      )

      # McpServerDeployJob.perform_async(new_deployment.id)

      {
        deployment: new_deployment.summary,
        rolled_back_from: current&.version
      }
    rescue ActiveRecord::RecordNotFound
      @errors << "Deployment not found"
      nil
    rescue StandardError => e
      @errors << e.message
      nil
    end

    def get_deployment_history(server_id, limit: 20)
      server = find_server(server_id)
      return nil unless server

      deployments = server.deployments
        .order(created_at: :desc)
        .limit(limit)

      {
        server_id: server_id,
        deployments: deployments.map(&:summary),
        current_deployment: server.current_deployment&.summary
      }
    end

    # ==========================================================================
    # SERVER LIFECYCLE
    # ==========================================================================

    def start_server(server_id, user: nil)
      server = find_server(server_id)
      return nil unless server

      unless %w[stopped failed pending].include?(server.status)
        @errors << "Server can only be started from stopped, failed, or pending state"
        return nil
      end

      # If server has a linked container template, delegate to DevOps orchestration
      if server.container_template.present?
        start_via_container(server, user)
      else
        server.start!
        server.reload.summary
      end
    rescue Devops::ContainerOrchestrationService::OrchestrationError => e
      @errors << "Container orchestration failed: #{e.message}"
      nil
    rescue StandardError => e
      @errors << e.message
      nil
    end

    def stop_server(server_id)
      server = find_server(server_id)
      return nil unless server

      unless %w[running deploying].include?(server.status)
        @errors << "Server can only be stopped when running"
        return nil
      end

      # If running via container, cancel through orchestration service
      if server.container_instance.present?
        stop_via_container(server)
      else
        server.stop!
      end

      server.reload.summary
    rescue Devops::ContainerOrchestrationService::OrchestrationError => e
      @errors << "Container orchestration failed: #{e.message}"
      nil
    rescue StandardError => e
      @errors << e.message
      nil
    end

    def restart_server(server_id, user: nil)
      server = find_server(server_id)
      return nil unless server

      if server.container_template.present? && server.container_instance.present?
        stop_via_container(server)
        start_via_container(server, user)
      else
        server.restart!
      end

      server.reload.summary
    rescue StandardError => e
      @errors << e.message
      nil
    end

    # ==========================================================================
    # METRICS & MONITORING
    # ==========================================================================

    def get_server_metrics(server_id, period: 24.hours, granularity: "hourly")
      server = find_server(server_id)
      return nil unless server

      metrics = server.metrics
        .where("recorded_at >= ?", period.ago)
        .where(granularity: granularity)
        .order(recorded_at: :asc)

      {
        server_id: server_id,
        period_hours: period.to_i / 3600,
        granularity: granularity,
        metrics: metrics.map(&:summary),
        summary: calculate_metrics_summary(metrics)
      }
    end

    def get_health_status(server_id)
      server = find_server(server_id)
      return nil unless server

      health = {
        server_id: server_id,
        status: server.status,
        health_status: server.health_status,
        last_health_check: server.last_health_check_at,
        uptime_percentage: server.uptime_percentage.to_f,
        current_deployment: server.current_deployment&.summary,
        container_backed: server.container_template.present?
      }

      # Add container instance status if running via orchestration
      if server.container_instance.present?
        instance = server.container_instance
        health[:container] = {
          execution_id: instance.execution_id,
          status: instance.status,
          started_at: instance.started_at,
          memory_used_mb: instance.memory_used_mb,
          cpu_used_millicores: instance.cpu_used_millicores
        }
      end

      health
    end

    # ==========================================================================
    # MARKETPLACE OPERATIONS
    # ==========================================================================

    def publish_to_marketplace(server_id, params = {})
      server = find_server(server_id)
      return nil unless server

      unless server.status == "running"
        @errors << "Only running servers can be published"
        return nil
      end

      server.update!(
        visibility: "marketplace",
        is_published: true,
        marketplace_category: params[:category],
        marketplace_price_usd: params[:price_usd] || 0,
        marketplace_description: params[:description] || server.description,
        published_at: Time.current
      )

      server.reload.summary
    rescue ActiveRecord::RecordInvalid => e
      @errors << e.message
      nil
    end

    def unpublish_from_marketplace(server_id)
      server = find_server(server_id)
      return nil unless server

      server.update!(
        visibility: "private",
        is_published: false
      )

      server.reload.summary
    rescue StandardError => e
      @errors << e.message
      nil
    end

    def browse_marketplace(category: nil, search: nil, limit: 50, offset: 0)
      scope = Mcp::HostedServer
        .where(visibility: "marketplace", is_published: true, status: "running")
        .order(subscription_count: :desc, created_at: :desc)
        .offset(offset)
        .limit(limit)

      scope = scope.where(marketplace_category: category) if category.present?
      scope = scope.where("name ILIKE ? OR description ILIKE ?", "%#{search}%", "%#{search}%") if search.present?

      {
        servers: scope.map(&:marketplace_summary),
        total_count: scope.except(:limit, :offset).count,
        limit: limit,
        offset: offset
      }
    end

    def subscribe_to_server(hosted_server_id, subscription_type: "free")
      server = Mcp::HostedServer.find(hosted_server_id)

      unless server.is_published?
        @errors << "Server is not available for subscription"
        return nil
      end

      existing = Mcp::ServerSubscription.find_by(
        account: account,
        hosted_server: server
      )

      if existing
        @errors << "Already subscribed to this server"
        return nil
      end

      subscription = Mcp::ServerSubscription.create!(
        account: account,
        hosted_server: server,
        status: "active",
        subscription_type: subscription_type,
        monthly_price_usd: server.marketplace_price_usd,
        monthly_request_limit: calculate_request_limit(subscription_type),
        current_period_start: Time.current,
        current_period_end: 1.month.from_now
      )

      server.increment!(:subscription_count)

      subscription.summary
    rescue ActiveRecord::RecordNotFound
      @errors << "Server not found"
      nil
    rescue ActiveRecord::RecordInvalid => e
      @errors << e.message
      nil
    end

    def get_subscriptions(status: nil, limit: 50, offset: 0)
      scope = Mcp::ServerSubscription
        .where(account: account)
        .includes(:hosted_server)
        .order(created_at: :desc)
        .offset(offset)
        .limit(limit)

      scope = scope.where(status: status) if status.present?

      {
        subscriptions: scope.map(&:summary),
        total_count: scope.except(:limit, :offset).count,
        limit: limit,
        offset: offset
      }
    end

    private

    # Container orchestration helpers

    def start_via_container(server, user)
      orchestration = Devops::ContainerOrchestrationService.new(
        account: account,
        user: user || server.deployed_by
      )

      instance = orchestration.execute(
        template: server.container_template,
        input_parameters: { mcp_server_id: server.mcp_server_id },
        timeout_seconds: server.container_template.timeout_seconds
      )

      server.update!(
        status: "deploying",
        container_instance: instance
      )

      # Update linked McpServer status if present
      server.mcp_server&.update!(status: "connecting")

      server.reload.summary
    end

    def stop_via_container(server)
      if server.container_instance&.active?
        orchestration = Devops::ContainerOrchestrationService.new(
          account: account,
          user: server.deployed_by
        )
        orchestration.cancel(server.container_instance.execution_id, reason: "MCP server stopped")
      end

      server.update!(
        status: "stopped",
        current_instances: 0,
        container_instance: nil
      )

      # Update linked McpServer status if present
      server.mcp_server&.update!(status: "disconnected")
    end

    def find_server(server_id)
      server = Mcp::HostedServer.find_by(id: server_id, account: account)
      unless server
        @errors << "Server not found"
        return nil
      end
      server
    end

    def default_resource_limits
      {
        memory_mb: 512,
        cpu_millicores: 500,
        timeout_seconds: 30,
        max_concurrent_requests: 10
      }
    end

    def generate_version(server)
      latest = server.deployments.maximum(:version)
      if latest&.match?(/^v\d+$/)
        "v#{latest.gsub('v', '').to_i + 1}"
      else
        "v1"
      end
    end

    def calculate_metrics_summary(metrics)
      return {} if metrics.empty?

      {
        avg_request_count: metrics.average(:request_count).to_f.round(2),
        total_requests: metrics.sum(:request_count),
        avg_latency_ms: metrics.average(:avg_latency_ms).to_f.round(2),
        avg_error_rate: metrics.average(:error_rate).to_f.round(4),
        avg_cpu_usage: metrics.average(:cpu_usage_percent).to_f.round(2),
        avg_memory_usage: metrics.average(:memory_usage_mb).to_f.round(2)
      }
    end

    def calculate_request_limit(subscription_type)
      case subscription_type
      when "free" then 100
      when "trial" then 1000
      when "monthly" then 10_000
      when "annual" then nil # unlimited
      else 100
      end
    end
  end
end

# frozen_string_literal: true

# MCP Hosted Server Model - Managed MCP server instances
#
# Provides managed hosting for MCP (Model Context Protocol) servers
# with auto-scaling, health monitoring, and marketplace integration.
#
module Mcp
  class HostedServer < ApplicationRecord
    self.table_name = "mcp_hosted_servers"

    # Associations
    belongs_to :account
    belongs_to :mcp_server, optional: true
    belongs_to :deployed_by, class_name: "User", optional: true
    belongs_to :container_template, class_name: "Devops::ContainerTemplate", optional: true
    belongs_to :container_instance, class_name: "Devops::ContainerInstance", optional: true
    has_many :deployments, class_name: "Mcp::ServerDeployment", foreign_key: :hosted_server_id, dependent: :destroy
    has_many :metrics, class_name: "Mcp::ServerMetric", foreign_key: :hosted_server_id, dependent: :destroy
    has_many :subscriptions, class_name: "Mcp::ServerSubscription", foreign_key: :hosted_server_id, dependent: :destroy

    # Validations
    validates :name, presence: true, length: { maximum: 100 }
    validates :name, uniqueness: { scope: :account_id }
    validates :server_type, presence: true
    validates :status, presence: true, inclusion: {
      in: %w[pending building deploying running stopped failed deleted]
    }
    validates :visibility, presence: true, inclusion: {
      in: %w[private team public marketplace]
    }
    validates :runtime, presence: true, inclusion: {
      in: %w[node python ruby go rust deno bun]
    }
    validates :source_type, presence: true, inclusion: {
      in: %w[git upload inline registry]
    }
    validates :memory_mb, numericality: { greater_than: 0 }, allow_nil: true
    validates :cpu_millicores, numericality: { greater_than: 0 }, allow_nil: true

    # Scopes
    scope :active, -> { where(status: %w[running deploying]) }
    scope :running, -> { where(status: "running") }
    scope :for_account, ->(account) { where(account: account) }
    scope :public_servers, -> { where(visibility: %w[public marketplace]) }
    scope :marketplace, -> { where(visibility: "marketplace", is_published: true) }
    scope :healthy, -> { where(health_status: "healthy") }
    scope :by_type, ->(type) { where(server_type: type) }
    scope :with_subscriptions, -> { joins(:subscriptions).distinct }

    # Callbacks
    before_create :set_defaults

    # Instance methods
    def running?
      status == "running"
    end

    def healthy?
      health_status == "healthy"
    end

    def can_deploy?
      %w[pending stopped failed].include?(status)
    end

    def can_stop?
      %w[running deploying].include?(status)
    end

    def start!
      return false unless can_deploy?

      update!(status: "deploying")
      # Trigger deployment job
      true
    end

    def stop!
      return false unless can_stop?

      update!(
        status: "stopped",
        current_instances: 0
      )
      true
    end

    def restart!
      return false unless running?

      update!(status: "deploying")
      # Trigger restart job
      true
    end

    def soft_delete!
      update!(status: "deleted")
      true
    end

    def current_deployment
      deployments.where(status: "running").order(created_at: :desc).first
    end

    def delete!
      update!(status: "deleted")
      # Cleanup resources
      true
    end

    def record_request(success:, latency_ms:, error_type: nil)
      self.total_requests += 1
      self.total_errors += 1 unless success

      # Update rolling average latency
      if avg_latency_ms
        self.avg_latency_ms = (avg_latency_ms * 0.9 + latency_ms * 0.1).round(2)
      else
        self.avg_latency_ms = latency_ms
      end

      save!
    end

    def success_rate
      return 0 if total_requests.zero?
      ((total_requests - total_errors).to_f / total_requests * 100).round(2)
    end

    def publish_to_marketplace!(price_per_request: nil, monthly_price: nil)
      return false unless %w[public marketplace].include?(visibility)

      update!(
        visibility: "marketplace",
        is_published: true,
        price_per_request: price_per_request,
        monthly_subscription_price: monthly_price
      )
    end

    def unpublish_from_marketplace!
      update!(
        is_published: false
      )
    end

    def tools
      tools_manifest || []
    end

    def summary
      {
        id: id,
        name: name,
        description: description,
        server_type: server_type,
        status: status,
        visibility: visibility,
        health_status: health_status,
        runtime: runtime,
        runtime_version: runtime_version,
        deployment_region: deployment_region,
        current_version: current_version,
        current_instances: current_instances,
        total_requests: total_requests,
        success_rate: success_rate,
        avg_latency_ms: avg_latency_ms&.to_f,
        total_cost_usd: total_cost_usd.to_f,
        tools_count: tools.length,
        is_published: is_published,
        marketplace_installs: marketplace_installs,
        marketplace_rating: marketplace_rating&.to_f,
        last_deployed_at: last_deployed_at,
        created_at: created_at
      }
    end

    def detailed_info
      summary.merge(
        tools_manifest: tools_manifest,
        capabilities: capabilities,
        environment_variables: environment_variables.keys,
        build_config: build_config,
        memory_mb: memory_mb,
        cpu_millicores: cpu_millicores,
        max_instances: max_instances,
        min_instances: min_instances,
        timeout_seconds: timeout_seconds,
        source_type: source_type,
        source_url: source_url,
        entry_point: entry_point
      )
    end

    def detailed_summary
      detailed_info.merge(
        current_deployment: current_deployment&.summary,
        recent_deployments: deployments.order(created_at: :desc).limit(5).map(&:summary),
        subscription_count: subscriptions.active.count
      )
    end

    def marketplace_summary
      {
        id: id,
        name: name,
        description: marketplace_description || description,
        category: marketplace_category,
        price_usd: marketplace_price_usd&.to_f,
        server_type: server_type,
        tools_count: tools.length,
        subscription_count: subscription_count,
        marketplace_rating: marketplace_rating&.to_f,
        publisher_account_id: account_id,
        published_at: published_at
      }
    end

    def uptime_percentage
      # Calculate uptime based on metrics
      recent_metrics = metrics.where("recorded_at >= ?", 30.days.ago)
      return 100.0 if recent_metrics.empty?

      healthy_count = recent_metrics.where(error_rate: 0..0.01).count
      (healthy_count.to_f / recent_metrics.count * 100).round(2)
    end

    private

    def set_defaults
      self.current_version ||= "1.0.0"
      self.health_status ||= "unknown"
    end
  end
end

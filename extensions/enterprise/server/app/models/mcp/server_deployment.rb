# frozen_string_literal: true

# MCP Server Deployment Model - Deployment history
#
# Records deployment history for hosted MCP servers.
#
module Mcp
  class ServerDeployment < ApplicationRecord
    self.table_name = "mcp_server_deployments"

    # Associations
    belongs_to :hosted_server, class_name: "Mcp::HostedServer"
    belongs_to :deployed_by, class_name: "User", optional: true
    belongs_to :rollback_from_deployment, class_name: "Mcp::ServerDeployment", optional: true

    # Validations
    validates :version, presence: true
    validates :status, presence: true, inclusion: {
      in: %w[pending building deploying running failed rolled_back superseded]
    }
    validates :deployment_type, presence: true, inclusion: {
      in: %w[manual automatic rollback scheduled]
    }

    # Scopes
    scope :successful, -> { where(status: "running") }
    scope :failed, -> { where(status: "failed") }
    scope :recent, ->(limit = 10) { order(created_at: :desc).limit(limit) }
    scope :for_server, ->(server) { where(hosted_server: server) }

    # Instance methods
    def successful?
      status == "running"
    end

    def failed?
      status == "failed"
    end

    def in_progress?
      %w[pending building deploying].include?(status)
    end

    def can_rollback?
      status == "running" && !is_rollback
    end

    def total_duration_seconds
      return nil unless build_completed_at && deployment_completed_at

      (deployment_completed_at - build_started_at).to_i
    end

    def start_build!
      update!(
        status: "building",
        build_started_at: Time.current
      )
    end

    def complete_build!(logs: nil)
      update!(
        status: "deploying",
        build_completed_at: Time.current,
        build_logs: logs,
        build_duration_seconds: build_started_at ? (Time.current - build_started_at).to_i : nil,
        deployment_started_at: Time.current
      )
    end

    def complete_deployment!(logs: nil)
      update!(
        status: "running",
        deployment_completed_at: Time.current,
        deployment_logs: logs,
        deployment_duration_seconds: deployment_started_at ? (Time.current - deployment_started_at).to_i : nil
      )

      # Update hosted server
      hosted_server.update!(
        status: "running",
        current_version: version,
        last_deployed_at: Time.current,
        deployed_by: deployed_by
      )

      # Mark previous deployments as superseded
      hosted_server.deployments
                   .where.not(id: id)
                   .where(status: "running")
                   .update_all(status: "superseded")
    end

    def fail!(error_message:, logs: nil)
      update!(
        status: "failed",
        error_message: error_message,
        deployment_logs: logs,
        deployment_completed_at: Time.current
      )

      hosted_server.update!(status: "failed")
    end

    def summary
      {
        id: id,
        version: version,
        status: status,
        deployment_type: deployment_type,
        source_commit: source_commit,
        is_rollback: is_rollback,
        build_duration_seconds: build_duration_seconds,
        deployment_duration_seconds: deployment_duration_seconds,
        total_duration_seconds: total_duration_seconds,
        error_message: error_message,
        deployed_by_id: deployed_by_id,
        created_at: created_at,
        deployment_completed_at: deployment_completed_at
      }
    end
  end
end

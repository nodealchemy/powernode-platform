# frozen_string_literal: true

module Devops
  class SwarmDeployment < ApplicationRecord
    self.table_name = "devops_swarm_deployments"

    include Auditable
    include ExecutionTrackable

    DEPLOYMENT_TYPES = %w[deploy update scale rollback remove stack_deploy stack_remove].freeze
    STATUSES = %w[pending running completed failed cancelled].freeze

    belongs_to :cluster, class_name: "Devops::SwarmCluster"
    belongs_to :service, class_name: "Devops::SwarmService", optional: true
    belongs_to :stack, class_name: "Devops::SwarmStack", optional: true
    belongs_to :triggered_by, class_name: "User", optional: true

    validates :deployment_type, presence: true, inclusion: { in: DEPLOYMENT_TYPES }
    validates :status, presence: true, inclusion: { in: STATUSES }

    scope :recent, -> { order(created_at: :desc) }
    scope :by_type, ->(type) { where(deployment_type: type) }
    scope :for_service, ->(service_id) { where(service_id: service_id) }
    scope :for_stack, ->(stack_id) { where(stack_id: stack_id) }

    def start!
      update!(status: "running", started_at: Time.current)
    end

    def complete!(result_data = {})
      update!(
        status: "completed",
        completed_at: Time.current,
        duration_ms: calculate_duration_ms,
        result: result_data
      )
    end

    def fail!(error_data = {})
      update!(
        status: "failed",
        completed_at: Time.current,
        duration_ms: calculate_duration_ms,
        result: error_data
      )
    end

    def deployment_summary
      {
        id: id,
        deployment_type: deployment_type,
        status: status,
        service_id: service_id,
        stack_id: stack_id,
        triggered_by: triggered_by&.full_name,
        trigger_source: trigger_source,
        started_at: started_at,
        completed_at: completed_at,
        duration_ms: duration_ms,
        created_at: created_at
      }
    end

    def deployment_details
      deployment_summary.merge(
        previous_state: previous_state,
        desired_state: desired_state,
        result: result,
        git_sha: git_sha,
        cluster_id: cluster_id
      )
    end

    private

    def calculate_duration_ms
      return nil unless started_at

      ((Time.current - started_at) * 1000).to_i
    end
  end
end

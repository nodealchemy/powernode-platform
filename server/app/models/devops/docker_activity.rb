# frozen_string_literal: true

module Devops
  class DockerActivity < ApplicationRecord
    self.table_name = "devops_docker_activities"

    include Auditable
    include ExecutionTrackable

    ACTIVITY_TYPES = %w[create start stop restart remove pull image_remove image_tag].freeze
    STATUSES = %w[pending running completed failed].freeze

    belongs_to :docker_host, class_name: "Devops::DockerHost"
    belongs_to :container, class_name: "Devops::DockerContainer", optional: true
    belongs_to :image, class_name: "Devops::DockerImage", optional: true
    belongs_to :triggered_by, class_name: "User", optional: true

    validates :activity_type, presence: true, inclusion: { in: ACTIVITY_TYPES }
    validates :status, presence: true, inclusion: { in: STATUSES }

    scope :recent, -> { order(created_at: :desc) }
    scope :by_type, ->(type) { where(activity_type: type) }
    scope :for_container, ->(container_id) { where(container_id: container_id) }
    scope :for_image, ->(image_id) { where(image_id: image_id) }

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

    def activity_summary
      {
        id: id,
        activity_type: activity_type,
        status: status,
        container_id: container_id,
        image_id: image_id,
        triggered_by: triggered_by&.full_name,
        trigger_source: trigger_source,
        started_at: started_at,
        completed_at: completed_at,
        duration_ms: duration_ms,
        created_at: created_at
      }
    end

    def activity_details
      activity_summary.merge(
        params: params,
        result: result,
        docker_host_id: docker_host_id
      )
    end

    private

    def calculate_duration_ms
      return nil unless started_at

      ((Time.current - started_at) * 1000).to_i
    end
  end
end

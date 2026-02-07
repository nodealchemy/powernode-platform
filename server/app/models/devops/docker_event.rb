# frozen_string_literal: true

module Devops
  class DockerEvent < ApplicationRecord
    self.table_name = "devops_docker_events"

    include Auditable

    SEVERITIES = %w[info warning error critical].freeze
    SOURCE_TYPES = %w[host container image network volume].freeze

    belongs_to :docker_host, class_name: "Devops::DockerHost"
    belongs_to :acknowledged_by, class_name: "User", optional: true

    validates :event_type, presence: true
    validates :severity, presence: true, inclusion: { in: SEVERITIES }
    validates :source_type, presence: true, inclusion: { in: SOURCE_TYPES }
    validates :message, presence: true

    scope :unacknowledged, -> { where(acknowledged: false) }
    scope :by_severity, ->(severity) { where(severity: severity) }
    scope :critical, -> { where(severity: "critical") }
    scope :recent, -> { order(created_at: :desc) }
    scope :since, ->(time) { where("created_at >= ?", time) }

    def acknowledge!(user)
      update!(
        acknowledged: true,
        acknowledged_by: user,
        acknowledged_at: Time.current
      )
    end

    def critical?
      severity == "critical"
    end

    def warning?
      severity == "warning"
    end

    def event_summary
      {
        id: id,
        event_type: event_type,
        severity: severity,
        source_type: source_type,
        source_name: source_name,
        message: message,
        acknowledged: acknowledged,
        created_at: created_at
      }
    end

    def event_details
      event_summary.merge(
        source_id: source_id,
        metadata: metadata,
        acknowledged_by: acknowledged_by&.full_name,
        acknowledged_at: acknowledged_at,
        docker_host_id: docker_host_id
      )
    end
  end
end

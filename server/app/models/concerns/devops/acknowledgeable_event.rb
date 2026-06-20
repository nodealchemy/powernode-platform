# frozen_string_literal: true

module Devops
  # Shared behavior for Docker and Swarm event models (Devops::DockerEvent,
  # Devops::SwarmEvent), which were byte-identical apart from their owner
  # association, SOURCE_TYPES, and the owner FK surfaced in #event_details.
  #
  # Each including model must:
  #   - define SOURCE_TYPES and validate :source_type inclusion against it
  #   - declare its owner belongs_to (e.g. :docker_host / :cluster)
  #   - override #event_owner_attributes to surface its owner FK in #event_details
  module AcknowledgeableEvent
    extend ActiveSupport::Concern

    SEVERITIES = %w[info warning error critical].freeze

    included do
      belongs_to :acknowledged_by, class_name: "User", optional: true

      validates :event_type, presence: true
      validates :severity, presence: true, inclusion: { in: SEVERITIES }
      validates :message, presence: true

      scope :unacknowledged, -> { where(acknowledged: false) }
      scope :by_severity, ->(severity) { where(severity: severity) }
      scope :critical, -> { where(severity: "critical") }
      scope :recent, -> { order(created_at: :desc) }
      scope :since, ->(time) { where("created_at >= ?", time) }
    end

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
        acknowledged_at: acknowledged_at
      ).merge(event_owner_attributes)
    end

    private

    # Owner FK surfaced in #event_details — overridden per model
    # (docker_host_id / cluster_id).
    def event_owner_attributes
      {}
    end
  end
end

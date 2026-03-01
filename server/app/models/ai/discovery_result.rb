# frozen_string_literal: true

module Ai
  class DiscoveryResult < ApplicationRecord
    self.table_name = "ai_discovery_results"

    # ==================== Constants ====================
    SCAN_TYPES = %w[mcp_scan docker_scan swarm_scan task_analysis full_scan].freeze
    STATUSES = %w[pending scanning completed failed].freeze

    # ==================== Associations ====================
    belongs_to :account

    # ==================== Validations ====================
    validates :scan_id, presence: true, uniqueness: true
    validates :scan_type, presence: true, inclusion: { in: SCAN_TYPES }
    validates :status, presence: true, inclusion: { in: STATUSES }

    # ==================== Scopes ====================
    scope :pending, -> { where(status: "pending") }
    scope :scanning, -> { where(status: "scanning") }
    scope :completed, -> { where(status: "completed") }
    scope :failed, -> { where(status: "failed") }
    scope :by_type, ->(type) { where(scan_type: type) }
    scope :recent, -> { order(created_at: :desc) }

    # ==================== Callbacks ====================
    before_validation :generate_scan_id, on: :create

    # ==================== Status Transitions ====================

    def start!
      raise "Cannot start scan in '#{status}' state" unless status == "pending"

      update!(status: "scanning", started_at: Time.current)
    end

    def complete!(agents: [], connections: [], tools: [], recommendations: [])
      raise "Cannot complete scan in '#{status}' state" unless status == "scanning"

      update!(
        status: "completed",
        discovered_agents: agents,
        discovered_connections: connections,
        discovered_tools: tools,
        recommendations: recommendations,
        agents_found: agents.size,
        connections_found: connections.size,
        tools_found: tools.size,
        completed_at: Time.current
      )
    end

    def fail!(message)
      update!(
        status: "failed",
        error_message: message,
        completed_at: Time.current
      )
    end

    # ==================== Instance Methods ====================

    def duration_ms
      return nil unless started_at && completed_at

      ((completed_at - started_at) * 1000).to_i
    end

    def scan_summary
      {
        id: id,
        scan_id: scan_id,
        scan_type: scan_type,
        status: status,
        agents_found: agents_found,
        connections_found: connections_found,
        tools_found: tools_found,
        duration_ms: duration_ms,
        started_at: started_at,
        completed_at: completed_at,
        error_message: error_message,
        created_at: created_at
      }
    end

    private

    def generate_scan_id
      self.scan_id ||= "scan_#{scan_type}_#{SecureRandom.hex(8)}"
    end
  end
end

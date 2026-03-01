# frozen_string_literal: true

module Ai
  class AgentConnection < ApplicationRecord
    self.table_name = "ai_agent_connections"

    # ==================== Associations ====================
    belongs_to :account

    # ==================== Validations ====================
    validates :connection_type, presence: true, inclusion: {
      in: %w[team_membership mcp_tool_usage a2a_communication shared_memory infrastructure],
      message: "%{value} is not a valid connection type"
    }
    validates :source_type, presence: true
    validates :source_id, presence: true
    validates :target_type, presence: true
    validates :target_id, presence: true
    validates :status, presence: true, inclusion: {
      in: %w[active inactive discovered],
      message: "%{value} is not a valid status"
    }
    validates :strength, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }

    # ==================== Scopes ====================
    scope :active, -> { where(status: "active") }
    scope :inactive, -> { where(status: "inactive") }
    scope :discovered, -> { where(status: "discovered") }
    scope :by_type, ->(type) { where(connection_type: type) }
    scope :for_source, ->(type, id) { where(source_type: type, source_id: id) }
    scope :for_target, ->(type, id) { where(target_type: type, target_id: id) }
    scope :involving, ->(type, id) {
      where(source_type: type, source_id: id)
        .or(where(target_type: type, target_id: id))
    }
    scope :team_memberships, -> { where(connection_type: "team_membership") }
    scope :mcp_tool_usages, -> { where(connection_type: "mcp_tool_usage") }
    scope :a2a_communications, -> { where(connection_type: "a2a_communication") }
    scope :shared_memories, -> { where(connection_type: "shared_memory") }
    scope :infrastructure_connections, -> { where(connection_type: "infrastructure") }

    # ==================== Instance Methods ====================

    def activate!
      update!(status: "active")
    end

    def deactivate!
      update!(status: "inactive")
    end

    def connection_summary
      {
        id: id,
        connection_type: connection_type,
        source: { type: source_type, id: source_id },
        target: { type: target_type, id: target_id },
        status: status,
        strength: strength,
        discovered_by: discovered_by,
        metadata: metadata,
        created_at: created_at
      }
    end
  end
end

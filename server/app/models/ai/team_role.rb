# frozen_string_literal: true

module Ai
  class TeamRole < ApplicationRecord
    self.table_name = "ai_team_roles"

    ROLE_TYPES = %w[manager coordinator worker specialist reviewer validator].freeze

    # Associations
    belongs_to :account
    belongs_to :agent_team, class_name: "AiAgentTeam"
    belongs_to :ai_agent, class_name: "AiAgent", optional: true

    has_many :assigned_tasks, class_name: "Ai::TeamTask", foreign_key: :assigned_role_id, dependent: :nullify
    has_many :sent_messages, class_name: "Ai::TeamMessage", foreign_key: :from_role_id, dependent: :nullify
    has_many :received_messages, class_name: "Ai::TeamMessage", foreign_key: :to_role_id, dependent: :nullify

    # Validations
    validates :role_name, presence: true
    validates :role_name, uniqueness: { scope: :agent_team_id }
    validates :role_type, presence: true, inclusion: { in: ROLE_TYPES }
    validates :max_concurrent_tasks, numericality: { greater_than: 0 }, allow_nil: true

    # Scopes
    scope :managers, -> { where(role_type: "manager") }
    scope :workers, -> { where(role_type: "worker") }
    scope :specialists, -> { where(role_type: "specialist") }
    scope :reviewers, -> { where(role_type: "reviewer") }
    scope :ordered_by_priority, -> { order(:priority_order) }
    scope :can_delegate, -> { where(can_delegate: true) }

    # Role checks
    def manager?
      role_type == "manager"
    end

    def coordinator?
      role_type == "coordinator"
    end

    def worker?
      role_type == "worker"
    end

    def specialist?
      role_type == "specialist"
    end

    def reviewer?
      role_type == "reviewer"
    end

    def validator?
      role_type == "validator"
    end

    # Task capacity
    def available_capacity
      max_concurrent_tasks - active_task_count
    end

    def has_capacity?
      available_capacity > 0
    end

    def active_task_count
      assigned_tasks.where(status: %w[assigned in_progress]).count
    end

    # Tool access
    def can_use_tool?(tool_name)
      return true if tools_allowed.blank?

      tools_allowed.include?(tool_name)
    end

    # Context access
    def can_access_context?(context_type)
      return true if context_access.blank?

      context_access[context_type] == true
    end

    # Capabilities
    def has_capability?(capability)
      capabilities.include?(capability)
    end

    # Escalation
    def can_escalate_to?(other_role)
      return false unless can_escalate

      other_role.priority_order < priority_order
    end
  end
end

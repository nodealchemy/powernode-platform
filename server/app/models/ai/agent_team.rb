# frozen_string_literal: true

# Ai::AgentTeam - CrewAI-style team orchestration for multi-agent collaboration
# Enables hierarchical, mesh, sequential, and parallel team coordination patterns
module Ai
  class AgentTeam < ApplicationRecord
    # ==========================================
    # Constants
    # ==========================================
    TEAM_TYPES = %w[hierarchical mesh sequential parallel].freeze
    COORDINATION_STRATEGIES = %w[manager_led consensus auction round_robin priority_based].freeze
    STATUSES = %w[active inactive archived].freeze

    # ==========================================
    # Associations
    # ==========================================
    belongs_to :account
    has_many :members, class_name: "Ai::AgentTeamMember", foreign_key: "ai_agent_team_id", dependent: :destroy
    has_many :agents, class_name: "Ai::Agent", through: :members, source: :agent

    # ==========================================
    # Validations
    # ==========================================
    validates :name, presence: true
    validates :name, uniqueness: { scope: :account_id }
    validates :team_type, inclusion: { in: TEAM_TYPES }
    validates :coordination_strategy, inclusion: { in: COORDINATION_STRATEGIES }
    validates :status, inclusion: { in: STATUSES }

    validate :validate_team_config_structure
    validate :validate_coordination_compatibility

    # ==========================================
    # Scopes
    # ==========================================
    scope :active, -> { where(status: "active") }
    scope :inactive, -> { where(status: "inactive") }
    scope :archived, -> { where(status: "archived") }
    scope :by_type, ->(type) { where(team_type: type) }
    scope :hierarchical, -> { where(team_type: "hierarchical") }
    scope :mesh, -> { where(team_type: "mesh") }
    scope :sequential, -> { where(team_type: "sequential") }
    scope :parallel, -> { where(team_type: "parallel") }

    # ==========================================
    # Callbacks
    # ==========================================
    before_validation :set_default_values, on: :create
    after_create :initialize_team_communication

    # ==========================================
    # Public Methods
    # ==========================================

    # Execute team with given input
    def execute(input:, user:)
      raise ArgumentError, "Team must be active" unless active?
      raise ArgumentError, "Team must have at least one member" if members.empty?

      orchestrator = Ai::AgentTeamOrchestrator.new(team: self, user: user)
      orchestrator.execute(input: input)
    end

    # Get team lead member (if any)
    def team_lead
      members.find_by(is_lead: true)
    end

    # Get ordered members for sequential execution
    def ordered_members
      members.order(:priority_order)
    end

    # Check if team has a lead
    def has_lead?
      team_lead.present?
    end

    # Get team statistics
    def team_stats
      {
        total_members: members.count,
        member_count: members.count,
        has_lead: has_lead?,
        team_type: team_type,
        coordination_strategy: coordination_strategy,
        status: status
      }
    end

    # Check if team is active
    def active?
      status == "active"
    end

    # Archive the team
    def archive!
      update!(status: "archived")
    end

    # Activate the team
    def activate!
      update!(status: "active")
    end

    # Deactivate the team
    def deactivate!
      update!(status: "inactive")
    end

    # Add a member to the team
    def add_member(agent:, role:, capabilities: [], priority_order: nil, is_lead: false)
      priority = if priority_order.nil?
                   max_priority = members.maximum(:priority_order) || -1
                   max_priority + 1
      else
                   priority_order
      end

      members.create!(
        agent: agent,
        role: role,
        capabilities: capabilities,
        priority_order: priority,
        is_lead: is_lead
      )
    end

    # Remove a member from the team
    def remove_member(agent)
      members.find_by(ai_agent_id: agent.is_a?(Ai::Agent) ? agent.id : agent)&.destroy
    end

    # ==========================================
    # Private Methods
    # ==========================================
    private

    def set_default_values
      self.team_config ||= {}
      self.status ||= "active"
      self.team_type ||= "hierarchical"
      self.coordination_strategy ||= "manager_led"
    end

    def validate_team_config_structure
      return if team_config.blank?

      unless team_config.is_a?(Hash)
        errors.add(:team_config, "must be a hash")
      end
    end

    def validate_coordination_compatibility
      # Hierarchical teams should use manager_led coordination
      if team_type == "hierarchical" && coordination_strategy == "consensus"
        errors.add(:coordination_strategy, "hierarchical teams should use manager_led or priority_based coordination")
      end

      # Sequential teams work best with priority_based or round_robin
      if team_type == "sequential" && coordination_strategy == "consensus"
        errors.add(:coordination_strategy, "sequential teams work best with priority_based or round_robin coordination")
      end

      # Mesh teams should use consensus or auction
      if team_type == "mesh" && coordination_strategy == "manager_led"
        errors.add(:coordination_strategy, "mesh teams should use consensus or auction coordination")
      end
    end

    def initialize_team_communication
      # Hook for setting up team communication channels via MultiAgentCommunicationHub
      Rails.logger.info "[Ai::AgentTeam] Team created: #{name} (#{id})"
    end
  end
end

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
    PARALLEL_MODES = %w[standard worktree].freeze

    # ==========================================
    # Associations
    # ==========================================
    belongs_to :account
    has_many :members, class_name: "Ai::AgentTeamMember", foreign_key: "ai_agent_team_id", dependent: :destroy
    has_many :agents, class_name: "Ai::Agent", through: :members, source: :agent
    has_many :task_reviews, class_name: "Ai::TaskReview", through: :members
    has_many :ai_team_roles, class_name: "Ai::TeamRole", foreign_key: "agent_team_id", dependent: :destroy
    has_many :ai_team_channels, class_name: "Ai::TeamChannel", foreign_key: "agent_team_id", dependent: :destroy
    has_many :team_executions, class_name: "Ai::TeamExecution", foreign_key: "agent_team_id", dependent: :destroy
    has_many :compound_learnings, class_name: "Ai::CompoundLearning", foreign_key: "ai_agent_team_id", dependent: :nullify

    # ==========================================
    # Validations
    # ==========================================
    validates :name, presence: true
    validates :name, uniqueness: { scope: :account_id }
    validates :team_type, inclusion: { in: TEAM_TYPES }
    validates :coordination_strategy, inclusion: { in: COORDINATION_STRATEGIES }
    validates :status, inclusion: { in: STATUSES }
    validates :parallel_mode, inclusion: { in: PARALLEL_MODES }, allow_nil: true

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
    after_create :log_team_creation

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
        member_count: members.count,
        has_lead: has_lead?,
        team_type: team_type,
        coordination_strategy: coordination_strategy,
        status: status
      }
    end

    # Validate team composition and return warnings/recommendations
    def validate_team_composition
      warnings = []
      recommendations = []
      loaded_members = members.to_a
      lead_count = loaded_members.count(&:is_lead)
      worker_count = loaded_members.count { |m| !m.is_lead }
      total = loaded_members.size

      # Hierarchical teams should have a lead
      if team_type == "hierarchical" && lead_count.zero? && total.positive?
        warnings << "Hierarchical team has no lead member"
        recommendations << "Assign a lead to coordinate workers"
      end

      # Workers-per-lead ratio check
      if lead_count.positive?
        ratio = worker_count.to_f / lead_count
        if ratio > 9
          warnings << "Workers-per-lead ratio is #{ratio.round(1)}:1 (10+ is unhealthy)"
          recommendations << "Add more leads or reduce workers"
        elsif ratio > 5
          warnings << "Workers-per-lead ratio is #{ratio.round(1)}:1 (6-9 needs attention)"
        end
      end

      # Sequential teams need at least 2 members
      if team_type == "sequential" && total < 2
        warnings << "Sequential teams need at least 2 members for meaningful execution"
        recommendations << "Add more members for sequential pipeline"
      end

      # No reviewer role suggestion
      unless loaded_members.any? { |m| m.role&.include?("reviewer") || m.role&.include?("review") }
        recommendations << "Consider adding a reviewer role for quality assurance"
      end

      # Store warnings in team_config
      update_column(:team_config, (team_config || {}).merge("composition_warnings" => warnings)) if warnings.any?

      { warnings: warnings, recommendations: recommendations }
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

    def log_team_creation
      Rails.logger.info "[Ai::AgentTeam] Team created: #{name} (#{id})"
    end
  end
end

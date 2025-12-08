# frozen_string_literal: true

# AiAgentTeam - CrewAI-style team orchestration for multi-agent collaboration
# Enables hierarchical, mesh, sequential, and parallel team coordination patterns
class AiAgentTeam < ApplicationRecord
  # ==========================================
  # Constants
  # ==========================================
  TEAM_TYPES = %w[hierarchical mesh sequential parallel].freeze
  COORDINATION_STRATEGIES = %w[manager_worker peer_to_peer hybrid].freeze
  STATUSES = %w[active inactive archived].freeze

  # ==========================================
  # Associations
  # ==========================================
  belongs_to :account
  has_many :ai_agent_team_members, dependent: :destroy
  has_many :ai_agents, through: :ai_agent_team_members

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
  scope :active, -> { where(status: 'active') }
  scope :inactive, -> { where(status: 'inactive') }
  scope :archived, -> { where(status: 'archived') }
  scope :by_type, ->(type) { where(team_type: type) }
  scope :hierarchical, -> { where(team_type: 'hierarchical') }
  scope :mesh, -> { where(team_type: 'mesh') }
  scope :sequential, -> { where(team_type: 'sequential') }
  scope :parallel, -> { where(team_type: 'parallel') }

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
    raise ArgumentError, 'Team must be active' unless active?
    raise ArgumentError, 'Team must have at least one member' if ai_agent_team_members.empty?

    orchestrator = AiAgentTeamOrchestrator.new(team: self, user: user)
    orchestrator.execute(input: input)
  end

  # Get team lead member (if any)
  def team_lead
    ai_agent_team_members.find_by(is_lead: true)
  end

  # Get ordered members for sequential execution
  def ordered_members
    ai_agent_team_members.order(:priority_order)
  end

  # Check if team has a lead
  def has_lead?
    team_lead.present?
  end

  # Get team statistics
  def team_stats
    {
      total_members: ai_agent_team_members.count,
      member_count: ai_agent_team_members.count,
      has_lead: has_lead?,
      team_type: team_type,
      coordination_strategy: coordination_strategy,
      status: status
    }
  end

  # Check if team is active
  def active?
    status == 'active'
  end

  # Archive the team
  def archive!
    update!(status: 'archived')
  end

  # Activate the team
  def activate!
    update!(status: 'active')
  end

  # Deactivate the team
  def deactivate!
    update!(status: 'inactive')
  end

  # Add a member to the team
  def add_member(agent:, role:, capabilities: [], priority_order: nil, is_lead: false)
    priority = if priority_order.nil?
                 max_priority = ai_agent_team_members.maximum(:priority_order) || -1
                 max_priority + 1
               else
                 priority_order
               end

    ai_agent_team_members.create!(
      ai_agent: agent,
      role: role,
      capabilities: capabilities,
      priority_order: priority,
      is_lead: is_lead
    )
  end

  # Remove a member from the team
  def remove_member(agent)
    ai_agent_team_members.find_by(ai_agent: agent)&.destroy
  end

  # ==========================================
  # Private Methods
  # ==========================================
  private

  def set_default_values
    self.team_config ||= {}
    self.status ||= 'active'
    self.team_type ||= 'hierarchical'
    self.coordination_strategy ||= 'manager_worker'
  end

  def validate_team_config_structure
    return if team_config.blank?

    unless team_config.is_a?(Hash)
      errors.add(:team_config, 'must be a hash')
    end
  end

  def validate_coordination_compatibility
    # Hierarchical teams should use manager_worker coordination
    if team_type == 'hierarchical' && coordination_strategy == 'peer_to_peer'
      errors.add(:coordination_strategy, 'hierarchical teams should use manager_worker or hybrid coordination')
    end

    # Sequential teams work best with manager_worker
    if team_type == 'sequential' && coordination_strategy == 'peer_to_peer'
      errors.add(:coordination_strategy, 'sequential teams work best with manager_worker coordination')
    end

    # Mesh teams should use peer_to_peer or hybrid
    if team_type == 'mesh' && coordination_strategy == 'manager_worker'
      errors.add(:coordination_strategy, 'mesh teams should use peer_to_peer or hybrid coordination')
    end
  end

  def initialize_team_communication
    # Hook for setting up team communication channels via MultiAgentCommunicationHub
    Rails.logger.info "[AiAgentTeam] Team created: #{name} (#{id})"
  end
end

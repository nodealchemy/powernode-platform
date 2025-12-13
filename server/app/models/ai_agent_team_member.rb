# frozen_string_literal: true

# AiAgentTeamMember - Represents an agent's role and responsibilities within a team
# Manages priority ordering, capabilities, and lead designation
class AiAgentTeamMember < ApplicationRecord
  # ==========================================
  # Constants
  # ==========================================
  ROLES = %w[manager researcher writer reviewer executor analyst coordinator facilitator].freeze

  # ==========================================
  # Associations
  # ==========================================
  belongs_to :ai_agent_team
  belongs_to :ai_agent

  # Delegate useful methods to ai_agent
  delegate :name, :description, :agent_type, to: :ai_agent, prefix: true
  delegate :account, to: :ai_agent_team

  # ==========================================
  # Validations
  # ==========================================
  validates :role, presence: true
  validates :ai_agent_id, uniqueness: { scope: :ai_agent_team_id,
                                       message: "already belongs to this team" }
  validates :priority_order, numericality: { greater_than_or_equal_to: 0 }

  validate :validate_capabilities_structure
  validate :validate_member_config_structure
  validate :validate_single_team_lead

  # ==========================================
  # Scopes
  # ==========================================
  scope :by_priority, -> { order(:priority_order) }
  scope :by_role, ->(role) { where(role: role) }
  scope :leads, -> { where(is_lead: true) }
  scope :non_leads, -> { where(is_lead: false) }
  scope :managers, -> { where(role: "manager") }
  scope :researchers, -> { where(role: "researcher") }
  scope :writers, -> { where(role: "writer") }
  scope :reviewers, -> { where(role: "reviewer") }

  # ==========================================
  # Callbacks
  # ==========================================
  before_validation :set_default_values, on: :create
  before_create :set_priority_order
  after_create :register_with_team
  after_destroy :cleanup_team_registration

  # ==========================================
  # Public Methods
  # ==========================================

  # Execute this member's role with given context
  def execute(context:, user:)
    # Execute agent with role-specific context
    execution_context = build_execution_context(context)

    ai_agent.execute(
      input: execution_context[:input],
      user: user,
      context: execution_context
    )
  end

  # Check if this member can perform a specific capability
  def can_perform?(capability)
    capabilities.include?(capability.to_s)
  end

  # Get member's contribution to team
  def contribution_stats
    {
      role: role,
      is_lead: is_lead,
      priority: priority_order,
      capabilities_count: capabilities.count,
      agent_name: ai_agent_name
    }
  end

  # Promote to team lead
  def promote_to_lead!
    # Demote any existing leads first
    ai_agent_team.ai_agent_team_members.leads.where.not(id: id).update_all(is_lead: false)
    update!(is_lead: true)
  end

  # Demote from team lead
  def demote_from_lead!
    update!(is_lead: false)
  end

  # Update priority order
  def set_priority(new_priority)
    update!(priority_order: new_priority)
  end

  # ==========================================
  # Private Methods
  # ==========================================
  private

  def set_default_values
    self.capabilities ||= []
    self.member_config ||= {}
    self.is_lead ||= false
  end

  def set_priority_order
    return unless ai_agent_team_id.present?

    # If priority_order was explicitly set by user, respect that value
    # will_save_change_to_priority_order? returns true when value was changed from database default
    return if will_save_change_to_priority_order?

    # Auto-assign priority based on existing team members (only when using database default)
    max_priority = AiAgentTeamMember
                     .where(ai_agent_team_id: ai_agent_team_id)
                     .maximum(:priority_order) || -1
    self.priority_order = max_priority + 1
  end

  def validate_capabilities_structure
    return if capabilities.blank?

    unless capabilities.is_a?(Array)
      errors.add(:capabilities, "must be an array")
      return
    end

    unless capabilities.all? { |cap| cap.is_a?(String) }
      errors.add(:capabilities, "must contain only strings")
    end
  end

  def validate_member_config_structure
    return if member_config.blank?

    unless member_config.is_a?(Hash)
      errors.add(:member_config, "must be a hash")
    end
  end

  def validate_single_team_lead
    return unless is_lead? && ai_agent_team_id.present?

    # Allow one lead per team (excluding self for updates)
    existing_leads = ai_agent_team.ai_agent_team_members.leads.where.not(id: id)
    if existing_leads.exists?
      errors.add(:is_lead, "team can only have one lead")
    end
  end

  def build_execution_context(context)
    {
      input: context[:input],
      team_id: ai_agent_team_id,
      team_name: ai_agent_team.name,
      member_role: role,
      is_lead: is_lead,
      priority: priority_order,
      capabilities: capabilities,
      team_context: context[:team_context] || {}
    }
  end

  def register_with_team
    Rails.logger.info "[AiAgentTeamMember] Member registered: #{ai_agent_name} as #{role} in #{ai_agent_team.name}"
  end

  def cleanup_team_registration
    Rails.logger.info "[AiAgentTeamMember] Member removed: #{ai_agent_name} from #{ai_agent_team.name}"
  end
end

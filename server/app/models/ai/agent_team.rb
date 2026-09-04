# frozen_string_literal: true

# Ai::AgentTeam - CrewAI-style team orchestration for multi-agent collaboration
# Enables hierarchical, mesh, sequential, and parallel team coordination patterns
module Ai
  class AgentTeam < ApplicationRecord
    # ==========================================
    # Constants
    # ==========================================
    TEAM_TYPES = %w[hierarchical mesh sequential parallel workspace].freeze
    # Must stay in sync with the DB check_coordination_strategy constraint.
    COORDINATION_STRATEGIES = %w[manager_led consensus auction round_robin priority_based].freeze
    STATUSES = %w[active inactive archived].freeze
    PARALLEL_MODES = %w[standard worktree].freeze

    # HIER-P4 — a CANONICAL team (the account's materialisation of a global
    # Ai::TeamTemplate) is read-only through every write door, like a canonical
    # agent. Raised by #guard_mutable!.
    class ReadOnlyCanonical < StandardError; end

    READ_ONLY_MESSAGE = "%<name>s is a canonical team (materialised from the global template " \
                        "%<template>s) and read-only — clone the template to customise a copy"

    # ==========================================
    # Associations
    # ==========================================
    belongs_to :account
    belongs_to :template, class_name: "Ai::TeamTemplate", foreign_key: "template_id", optional: true
    has_many :members, class_name: "Ai::AgentTeamMember", foreign_key: "ai_agent_team_id", dependent: :destroy
    has_many :agents, class_name: "Ai::Agent", through: :members, source: :agent
    has_many :ai_team_roles, class_name: "Ai::TeamRole", foreign_key: "agent_team_id", dependent: :destroy
    has_many :ai_team_channels, class_name: "Ai::TeamChannel", foreign_key: "agent_team_id", dependent: :destroy
    has_many :team_executions, class_name: "Ai::TeamExecution", foreign_key: "agent_team_id", dependent: :destroy
    has_many :conversations, class_name: "Ai::Conversation", foreign_key: "agent_team_id", dependent: :nullify
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
    scope :workspaces, -> { where(team_type: "workspace") }
    # The per-account materialisation of a CANONICAL Ai::TeamTemplate (HIER-P4):
    # flagged in team_config by Ai::Teams::CanonicalTeamReconciler, the only
    # writer of its membership. A team merely CLONED from that template
    # (TeamTemplate#create_team!) carries the template_id but not the flag.
    # `@>` (not `->>'canonical' = 'true'`) so the SQL and #canonical? agree:
    # a hand-edited JSON STRING "true" reads as 'true' through ->> but is not
    # the Ruby `true` the predicate requires.
    scope :canonical, -> { where.not(template_id: nil).where("team_config @> ?", { canonical: true }.to_json) }

    # ==========================================
    # Callbacks
    # ==========================================
    before_validation :set_default_values, on: :create
    after_create :log_team_creation

    # ==========================================
    # Public Methods
    # ==========================================

    # True for the account's materialisation of a canonical template: read-only
    # through EVERY write door (the MCP verbs, both REST controllers and
    # Ai::Teams::CrudService — clone the template to customise), membership
    # repaired by the reconciler on `system:governance:reconcile`.
    def canonical?
      template_id.present? && team_config.is_a?(Hash) && team_config["canonical"] == true
    end

    # The ONE refusal wording, so the MCP envelope and the REST 403 cannot
    # drift apart.
    def canonical_read_only_message
      format(READ_ONLY_MESSAGE, name: name, template: canonical_template_label)
    end

    def canonical_template_label
      label = team_config["template_slug"] if team_config.is_a?(Hash)
      label.presence || template_id
    end

    # Called by every write door before it mutates. Raising (rather than
    # rendering from an action body) is what makes the guard HALT — a render
    # in the body would leave the write to land.
    def guard_mutable!
      raise ReadOnlyCanonical, canonical_read_only_message if canonical?

      true
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

    def require_plan_approval?
      team_config&.dig("require_plan_approval") == true
    end

    def coordinator_enabled?
      team_config&.dig("coordinator_enabled") != false
    end

    def lead_agent
      team_lead&.agent
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
    # Event-driven activation (T4)
    # ==========================================
    # Teams opt in by setting team_config["activation_rules"] to:
    #   {
    #     "on_event":         ["fleet.capacity_pressure", "fleet.region_busy"],
    #     "enabled":          true,
    #     "min_strength":     0.5,    # optional, default 0.0
    #     "cooldown_seconds": 600     # optional, default 0
    #   }
    # Each matching Ai::StigmergicSignal#after_create_commit fires
    # Ai::TeamEventDispatcher which calls #dispatch_for_event! on every
    # responsive team. activation_rules lives inside the existing
    # team_config JSONB (no new column needed).

    def activation_rules
      rules = team_config.is_a?(Hash) ? team_config["activation_rules"] : nil
      rules.is_a?(Hash) ? rules : {}
    end

    def event_subscriptions
      Array(activation_rules["on_event"])
    end

    def event_triggers_enabled?
      activation_rules["enabled"] == true && event_subscriptions.any?
    end

    def responsive_to_signal?(signal)
      return false unless event_triggers_enabled?
      return false unless event_subscriptions.include?(signal.signal_key)
      return false unless active?

      min_strength = activation_rules["min_strength"].to_f
      return false if min_strength.positive? && signal.strength.to_f < min_strength

      cooldown = activation_rules["cooldown_seconds"].to_i
      if cooldown.positive?
        last = Array(team_config.to_h["event_history"]).first
        if last && last["dispatched_at"]
          last_at = Time.parse(last["dispatched_at"].to_s)
          return false if last_at > cooldown.seconds.ago
        end
      end

      true
    rescue ArgumentError
      true
    end

    def dispatch_for_event!(signal, user: nil)
      execution = ::Ai::Teams::ExecutionService.new(account: account).start_execution(
        id,
        {
          objective: "Triggered by signal: #{signal.signal_key}",
          input_context: {
            "triggered_by_event"   => signal.signal_key,
            "signal_id"            => signal.id,
            "signal_type"          => signal.signal_type,
            "signal_strength"      => signal.strength,
            "signal_payload"       => signal.payload,
            "emitted_by_agent_id"  => signal.emitter_agent_id
          }
        },
        user: user
      )

      record_event_dispatch!(signal, execution)
      execution
    end

    def record_event_dispatch!(signal, execution)
      history = Array(team_config.to_h["event_history"])
      history.unshift(
        "signal_key"   => signal.signal_key,
        "signal_id"    => signal.id,
        "execution_id" => execution.respond_to?(:execution_id) ? execution.execution_id : execution&.id,
        "dispatched_at" => Time.current.iso8601
      )
      update!(team_config: team_config.to_h.merge("event_history" => history.first(20)))
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
      # Workspace teams are flexible - skip coordination validation
      return if team_type == "workspace"

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

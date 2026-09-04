# frozen_string_literal: true

module Ai
  class TeamTemplate < ApplicationRecord
    include GloballyScopable

    self.table_name = "ai_team_templates"

    TOPOLOGIES = %w[hierarchical flat mesh pipeline hybrid].freeze

    # Associations
    belongs_to :account, optional: true
    belongs_to :created_by, class_name: "User", foreign_key: "created_by_id", optional: true
    has_many :teams, class_name: "Ai::AgentTeam", foreign_key: "template_id", dependent: :nullify

    # Validations
    validates :name, presence: true
    validates :slug, presence: true, uniqueness: true
    validates :team_topology, inclusion: { in: TOPOLOGIES }

    # Scopes
    scope :system_templates, -> { where(is_system: true) }
    scope :user_templates, -> { where(is_system: false) }
    scope :public_templates, -> { where(is_public: true) }
    scope :published, -> { where.not(published_at: nil) }
    scope :by_category, ->(cat) { where(category: cat) }
    scope :by_topology, ->(top) { where(team_topology: top) }
    scope :popular, -> { order(usage_count: :desc) }
    scope :top_rated, -> { where.not(average_rating: nil).order(average_rating: :desc) }
    # CANONICAL teams (HIER-P4): the seeded, global, is_system, source_key-managed
    # templates whose role_definitions name canonical agents by slug. Each is
    # materialised per account by Ai::Teams::CanonicalTeamReconciler and is
    # read-only through the API — clone it to customise, like a canonical agent.
    scope :canonical, -> { global.system_templates.where.not(source_key: [ nil, "" ]) }

    # Callbacks
    before_validation :generate_slug, on: :create

    # Publishing
    def publish!
      update!(is_public: true, published_at: Time.current)
    end

    def unpublish!
      update!(is_public: false, published_at: nil)
    end

    def published?
      published_at.present?
    end

    # Usage tracking
    def record_usage!
      increment!(:usage_count)
    end

    # Rating
    def update_rating!(new_rating, total_ratings)
      # Weighted average calculation
      current_weight = usage_count - 1
      new_avg = if current_weight.positive? && average_rating.present?
                  ((average_rating * current_weight) + new_rating) / total_ratings
      else
                  new_rating
      end
      update!(average_rating: new_avg)
    end

    def canonical?
      global? && is_system && source_key.present?
    end

    # The role definitions that bind a canonical agent (`agent_slug`), in
    # priority order — the NODES of the team graph. Only a canonical template
    # carries these; a free-form template's roles have no agent binding.
    def member_definitions
      Array(role_definitions).select { |d| d.is_a?(Hash) && d["agent_slug"].present? }
                             .sort_by { |d| d["priority"].to_i }
    end

    def manager_definition
      member_definitions.find { |d| d["is_lead"] == true }
    end

    # Create team from template
    def create_team!(account:, name: nil, user: nil)
      team = Ai::AgentTeam.create!(
        account: account,
        name: name.presence || default_team_name_for(account),
        description: description,
        team_type: team_topology,
        team_topology: team_topology,
        coordination_strategy: default_config["coordination_strategy"] || "manager_led",
        communication_pattern: default_config["communication_pattern"] || "hub_spoke",
        team_config: default_config,
        template_id: id
      )

      # Create roles from template
      role_definitions.each do |role_def|
        Ai::TeamRole.create!(
          account: account,
          agent_team: team,
          role_name: role_def["name"],
          role_type: role_def["type"] || "worker",
          role_description: role_def["description"],
          responsibilities: role_def["responsibilities"],
          goals: role_def["goals"],
          capabilities: role_def["capabilities"] || [],
          constraints: role_def["constraints"] || [],
          tools_allowed: role_def["tools"] || [],
          priority_order: role_def["priority"] || 0,
          can_delegate: role_def["can_delegate"] || false,
          can_escalate: role_def["can_escalate"] || true,
          max_concurrent_tasks: role_def["max_concurrent_tasks"] || 1
        )
      end

      # Create channels from template
      channel_definitions.each do |channel_def|
        Ai::TeamChannel.create!(
          agent_team: team,
          name: channel_def["name"],
          channel_type: channel_def["type"] || "broadcast",
          description: channel_def["description"],
          is_persistent: channel_def["persistent"] != false,
          message_retention_hours: channel_def["retention_hours"],
          routing_rules: channel_def["routing_rules"] || {}
        )
      end

      record_usage!
      team
    end

    # The clone-to-customise default name. Ai::AgentTeam validates name
    # uniqueness per account, and a CANONICAL template's own name is already
    # taken by the account's materialised canonical team — so defaulting to
    # `self.name` raised RecordInvalid on exactly the path the docs tell a
    # reader to use (POST /api/v1/ai/teams with template_id passes name: nil).
    def default_team_name_for(account)
      return name unless account.ai_agent_teams.exists?(name: name)

      (2..99).each do |n|
        candidate = "#{name} (#{n})"
        return candidate unless account.ai_agent_teams.exists?(name: candidate)
      end

      "#{name} (#{SecureRandom.hex(4)})"
    end

    def template_summary
      {
        id: id,
        name: name,
        slug: slug,
        description: description,
        category: category,
        team_topology: team_topology,
        is_system: is_system,
        usage_count: usage_count,
        average_rating: average_rating,
        tags: tags
      }
    end

    # Template preview
    def preview
      {
        name: name,
        description: description,
        topology: team_topology,
        roles: role_definitions.map { |r| { name: r["name"], type: r["type"] } },
        channels: channel_definitions.map { |c| { name: c["name"], type: c["type"] } },
        workflow: workflow_pattern
      }
    end

    private

    def generate_slug
      return if slug.present?

      base_slug = name.parameterize
      self.slug = base_slug

      counter = 1
      while TeamTemplate.exists?(slug: slug)
        self.slug = "#{base_slug}-#{counter}"
        counter += 1
      end
    end
  end
end

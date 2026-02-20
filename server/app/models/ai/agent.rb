# frozen_string_literal: true

# AI Agent Model - MCP-only implementation for tool registration and execution
# Completely replaces legacy event-based communication with MCP protocol
module Ai
  class Agent < ApplicationRecord
    # Core concerns
    include Auditable
    include Searchable

    # Extracted concerns
    include Ai::Agent::StatusChecks
    include Ai::Agent::McpTool
    include Ai::Agent::McpRegistration
    include Ai::Agent::McpSchemas
    include Ai::Agent::Execution
    include Ai::Agent::Statistics
    include Ai::Agent::Operations
    include Ai::AgentStorageConfig

    # Associations
    belongs_to :account
    belongs_to :creator, class_name: "User", foreign_key: "creator_id"
    belongs_to :provider, class_name: "Ai::Provider", foreign_key: "ai_provider_id"
    has_many :executions, class_name: "Ai::AgentExecution", foreign_key: "ai_agent_id", dependent: :destroy

    has_many :conversations, class_name: "Ai::Conversation", foreign_key: "ai_agent_id", dependent: :destroy
    has_many :messages, class_name: "Ai::Message", foreign_key: "ai_agent_id", dependent: :destroy
    has_many :agent_skills, class_name: "Ai::AgentSkill", foreign_key: "ai_agent_id", dependent: :destroy
    has_many :skills, class_name: "Ai::Skill", through: :agent_skills, source: :skill

    # Autonomy system associations
    belongs_to :parent_agent, class_name: "Ai::Agent", foreign_key: "parent_agent_id", optional: true
    has_many :child_lineages, class_name: "Ai::AgentLineage", foreign_key: "parent_agent_id", dependent: :destroy
    has_many :child_agents, through: :child_lineages, source: :child_agent
    has_many :parent_lineages, class_name: "Ai::AgentLineage", foreign_key: "child_agent_id", dependent: :destroy
    has_many :parent_agents_via_lineage, through: :parent_lineages, source: :parent_agent
    has_one :trust_score, class_name: "Ai::AgentTrustScore", foreign_key: "agent_id", dependent: :destroy
    has_many :budgets, class_name: "Ai::AgentBudget", foreign_key: "agent_id", dependent: :destroy
    has_many :telemetry_events, class_name: "Ai::TelemetryEvent", foreign_key: "agent_id", dependent: :destroy
    has_many :shadow_executions, class_name: "Ai::ShadowExecution", foreign_key: "agent_id", dependent: :destroy
    has_many :short_term_memories, class_name: "Ai::AgentShortTermMemory", foreign_key: "agent_id", dependent: :destroy
    has_many :agent_team_members, class_name: "Ai::AgentTeamMember", foreign_key: "ai_agent_id"
    has_many :teams, class_name: "Ai::AgentTeam", through: :agent_team_members, source: :team

    # Validations
    validates :name, presence: true, length: { maximum: 255 }, uniqueness: { scope: :account_id }
    validates :description, length: { maximum: 1000 }
    validates :slug, presence: true, uniqueness: { scope: :account_id }, length: { maximum: 150 },
                     format: { with: /\A[a-z0-9\-_]+\z/, message: "can only contain lowercase letters, numbers, hyphens, and underscores" }
    validates :agent_type, presence: true, inclusion: {
      in: %w[assistant code_assistant data_analyst content_generator image_generator workflow_optimizer workflow_operations monitor],
      message: "is not included in the list"
    }
    validates :status, inclusion: { in: %w[active inactive paused error archived] }
    validates :version, format: { with: /\A\d+\.\d+\.\d+\z/, message: "must be in semantic version format (x.y.z)" }

    # JSON attributes for MCP data
    attribute :mcp_tool_manifest, :json, default: -> { {} }
    attribute :mcp_input_schema, :json, default: -> { default_input_schema }
    attribute :mcp_output_schema, :json, default: -> { default_output_schema }
    attribute :mcp_metadata, :json, default: -> { {} }
    attribute :conversation_profile, :json, default: -> { {} }

    # Scheduled messages
    has_many :scheduled_messages, through: :conversations, class_name: "Ai::ScheduledMessage"

    # Scopes
    scope :active, -> { where(status: "active") }
    scope :inactive, -> { where(status: "inactive") }
    scope :paused, -> { where(status: "paused") }
    scope :archived, -> { where(status: "archived") }
    scope :by_type, ->(type) { where(agent_type: type) }
    scope :by_creator, ->(user) { where(creator: user) }
    scope :mcp_enabled, -> { where.not(mcp_tool_manifest: {}) }
    scope :with_skill, ->(slug) {
      joins(:skills).where(ai_skills: { slug: slug, status: "active" })
    }
    scope :with_any_skills, ->(slugs) {
      joins(:skills).where(ai_skills: { slug: slugs, status: "active" }).distinct
    }
    scope :with_all_skills, ->(slugs) {
      joins(:skills)
        .where(ai_skills: { slug: slugs, status: "active" })
        .group("ai_agents.id")
        .having("COUNT(DISTINCT ai_skills.slug) = ?", slugs.size)
    }
    scope :recently_executed, ->(days = 30) { where("last_executed_at >= ?", days.days.ago) }
    scope :healthy, -> { where(status: "active") }
    scope :search_by_text, ->(query) {
      where("name ILIKE ? OR description ILIKE ?", "%#{query}%", "%#{query}%")
    }
    scope :concierge, -> { where(is_concierge: true) }
    scope :default_concierge, -> { concierge.active.order(:created_at).limit(1) }

    # Callbacks
    before_validation :generate_slug, if: -> { name.present? && (slug.blank? || name_changed?) }
    before_validation :normalize_agent_type
    before_save :update_version_if_mcp_changed
    before_save :ensure_mcp_tool_manifest
    after_commit :sync_to_knowledge_graph, on: [:create, :update]

    def skill_slugs
      agent_skills.where(is_active: true).joins(:skill).where(ai_skills: { status: "active" }).pluck("ai_skills.slug")
    end

    # Conversation profile accessors
    def conversation_tone
      conversation_profile["tone"]
    end

    def conversation_verbosity
      conversation_profile["verbosity"]
    end

    def build_system_prompt_with_profile
      base_prompt = mcp_metadata&.dig("system_prompt") || ""
      return base_prompt if conversation_profile.blank?

      profile_lines = []
      profile_lines << "PERSONALITY TRAITS:" if conversation_profile.any?
      profile_lines << "- Tone: #{conversation_profile['tone']}" if conversation_profile["tone"].present?
      profile_lines << "- Verbosity: #{conversation_profile['verbosity']}" if conversation_profile["verbosity"].present?
      profile_lines << "- Style: #{conversation_profile['style']}" if conversation_profile["style"].present?
      profile_lines << "- Greeting: #{conversation_profile['greeting']}" if conversation_profile["greeting"].present?

      custom_traits = conversation_profile.except("tone", "verbosity", "style", "greeting")
      custom_traits.each do |key, value|
        profile_lines << "- #{key.humanize}: #{value}"
      end

      [base_prompt, profile_lines.join("\n")].reject(&:blank?).join("\n\n")
    end

    private

    def sync_to_knowledge_graph
      return unless account_id.present?

      Ai::SkillGraph::BridgeService.new(account).sync_agent(self)
    rescue StandardError => e
      Rails.logger.warn "[Ai::Agent] KG sync failed for agent #{id}: #{e.message}"
    end

    def generate_slug
      return if name.blank?

      base_slug = name.downcase.gsub(/[^a-z0-9\s\-_]/, "").squeeze(" ").strip.gsub(/\s+/, "-")
      self.slug = base_slug

      # Ensure uniqueness within account
      counter = 1
      while account.ai_agents.where(slug: self.slug).where.not(id: id).exists?
        self.slug = "#{base_slug}-#{counter}"
        counter += 1
      end
    end

    def normalize_agent_type
      self.agent_type = agent_type&.downcase&.strip
    end

    def update_version_if_mcp_changed
      if mcp_tool_manifest_changed? || mcp_input_schema_changed? || mcp_output_schema_changed?
        increment_version
      end
    end

    def increment_version
      if version.present?
        version_parts = version.split(".").map(&:to_i)
        version_parts[2] += 1  # Increment patch version
        self.version = version_parts.join(".")
      else
        self.version = "1.0.0"
      end
    end

    def ensure_mcp_tool_manifest
      # Auto-generate MCP tool manifest if missing or incomplete, or if name changed
      if mcp_tool_manifest.blank? || !has_required_manifest_fields? || name_changed?
        self.mcp_tool_manifest = generate_mcp_tool_manifest
        self.mcp_registered_at = Time.current
      end
    end
  end
end

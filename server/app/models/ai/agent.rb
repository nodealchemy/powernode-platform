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
    has_one :agent_card, class_name: "Ai::AgentCard", foreign_key: "ai_agent_id", dependent: :nullify
    has_many :ralph_loops, class_name: "Ai::RalphLoop", foreign_key: "default_agent_id"

    # Validations
    validates :name, presence: true, length: { maximum: 255 }, uniqueness: { scope: :account_id }
    validates :description, length: { maximum: 1000 }
    validates :slug, presence: true, uniqueness: { scope: :account_id }, length: { maximum: 150 },
                     format: { with: /\A[a-z0-9\-_]+\z/, message: "can only contain lowercase letters, numbers, hyphens, and underscores" }
    validates :agent_type, presence: true, inclusion: {
      in: %w[assistant code_assistant data_analyst content_generator image_generator monitor mcp_client],
      message: "is not included in the list"
    }
    validates :status, inclusion: { in: %w[active inactive paused error archived] }
    validates :version, format: { with: /\A\d+\.\d+\.\d+\z/, message: "must be in semantic version format (x.y.z)" }
    validate :model_matches_provider, if: -> { provider.present? && mcp_metadata&.dig("model_config", "model").present? }
    validate :model_suitable_for_agent_type, if: -> { provider.present? && mcp_metadata&.dig("model_config", "model").present? }

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
    scope :mcp_clients, -> { where(agent_type: "mcp_client") }
    scope :active_mcp_clients, -> { mcp_clients.active }

    # Callbacks
    before_validation :generate_slug, if: -> { name.present? && (slug.blank? || name_changed?) }
    before_validation :normalize_agent_type
    before_validation :auto_resolve_provider_from_model, if: -> { mcp_metadata_changed? && mcp_metadata&.dig("model_config", "model").present? }
    before_save :update_version_if_mcp_changed
    before_save :ensure_mcp_tool_manifest
    after_commit :sync_to_knowledge_graph, on: [:create, :update]
    after_commit :notify_mcp_resources_changed, on: [:create, :destroy]
    after_commit :notify_mcp_resources_changed, if: :saved_change_to_status?

    def skill_slugs
      agent_skills.where(is_active: true).joins(:skill).where(ai_skills: { status: "active" }).pluck("ai_skills.slug")
    end

    # Required permissions for interacting with this agent (conversations, Ralph loops, etc.)
    # Stored in mcp_metadata["required_permissions"] as an array of permission strings.
    def required_permissions
      mcp_metadata&.dig("required_permissions") || []
    end

    # Conversation profile accessors
    def conversation_tone
      conversation_profile["tone"]
    end

    def conversation_verbosity
      conversation_profile["verbosity"]
    end

    def build_system_prompt_with_profile(context: nil)
      base_prompt = mcp_metadata&.dig("system_prompt") || ""
      skill_prompts = build_skill_system_prompts(context: context)

      profile_lines = []
      if conversation_profile.present?
        profile_lines << "PERSONALITY TRAITS:" if conversation_profile.any?
        profile_lines << "- Tone: #{conversation_profile['tone']}" if conversation_profile["tone"].present?
        profile_lines << "- Verbosity: #{conversation_profile['verbosity']}" if conversation_profile["verbosity"].present?
        profile_lines << "- Style: #{conversation_profile['style']}" if conversation_profile["style"].present?
        profile_lines << "- Greeting: #{conversation_profile['greeting']}" if conversation_profile["greeting"].present?

        custom_traits = conversation_profile.except("tone", "verbosity", "style", "greeting")
        custom_traits.each do |key, value|
          profile_lines << "- #{key.humanize}: #{value}"
        end
      end

      [base_prompt, skill_prompts, profile_lines.join("\n")].reject(&:blank?).join("\n\n")
    end

    # Runtime model resolution — agents own model selection. With a pinned model
    # (mcp_metadata.model_config.model) the agent's own provider is honored;
    # otherwise Ai::AgentModelSelector picks the best (provider, model) across ANY
    # active, credentialed provider in the account (cost/capability/empirical-aware,
    # honoring model_config.model_requirements). The matching active credential is
    # resolved for whichever provider wins. Returned as one memoized, coherent
    # triple so model, provider, and credential never disagree. Call sites (and the
    # worker's provider_config endpoint) should prefer these over the raw
    # model_config dig + agent.provider so unpinned agents resolve a current model.
    def model_resolution
      return @model_resolution if defined?(@model_resolution)

      @model_resolution = compute_model_resolution
    rescue StandardError => e
      # Don't memoize a transient failure — recompute next call so resolution
      # recovers once the cause (DB blip / selector error) clears.
      Rails.logger.error("[Ai::Agent#model_resolution] #{e.class}: #{e.message}")
      fallback_resolution
    end

    def resolved_model
      model_resolution[:model]
    end

    def resolved_provider
      model_resolution[:provider]
    end

    def resolved_credential
      model_resolution[:credential]
    end

    private

    # The coherent (model, provider, credential) triple. A pinned model is honored
    # only when it belongs to a usable provider (preferring the agent's own);
    # otherwise — and for unpinned agents — the selector picks across active
    # credentialed providers, folding in the agent's own + its skills' model
    # requirements. The credential always comes from the *resolved* provider, so the
    # three never disagree. Raises on selector failure (model_resolution rescues).
    def compute_model_resolution
      pinned = mcp_metadata&.dig("model_config", "model").presence
      if pinned && (prov = provider_for_pinned_model(pinned))
        return resolution_for(pinned, prov)
      end

      rec  = ::Ai::AgentModelSelector.recommend(
        account:      account,
        agent_type:   agent_type,
        requirements: merged_model_requirements
      )
      prov = rec[:provider] || provider
      resolution_for(rec[:model] || prov&.default_model, prov)
    end

    def resolution_for(model, prov)
      { model: model, provider: prov, credential: prov&.active_credential }
    end

    def fallback_resolution
      resolution_for(provider&.default_model, provider)
    end

    # The provider that can actually serve a pinned model: the agent's own when it
    # lists the model, else an account provider whose family matches the model id.
    # nil ⇒ the pin matches no usable provider, so the caller falls through to the
    # selector — restoring the supported-model safety check the old resolve_model had.
    def provider_for_pinned_model(model_id)
      return provider if provider && provider_lists_model?(provider, model_id)

      ptype = provider_type_for_model(model_id)
      return nil unless ptype

      account.ai_providers.active.where(provider_type: ptype).detect { |p| provider_lists_model?(p, model_id) } ||
        account.ai_providers.active.find_by(provider_type: ptype)
    end

    def provider_lists_model?(prov, model_id)
      Array(prov.supported_models).any? { |entry| ::Ai::ModelTiers.id_for(entry) == model_id }
    end

    # The agent's own model_requirements merged with its active skills' — capability
    # union, preferred union, most-demanding tier — so a skill like "devils-advocate"
    # (tier: reasoning) actually steers selection (previously inert).
    def merged_model_requirements
      ([ mcp_metadata&.dig("model_config", "model_requirements") ] + active_skill_model_requirements)
        .compact.reject(&:blank?)
        .reduce({}) do |acc, req|
          req = req.symbolize_keys
          {
            capabilities: (Array(acc[:capabilities]) + Array(req[:capabilities])).uniq,
            preferred:    (Array(acc[:preferred])    + Array(req[:preferred])).uniq,
            tier:         ::Ai::ModelTiers.max_tier(acc[:tier], req[:tier])
          }.compact
        end
    end

    def active_skill_model_requirements
      agent_skills.where(is_active: true)
                  .joins(:skill)
                  .where(ai_skills: { status: "active", is_enabled: true })
                  .pluck("ai_skills.model_requirements")
    end

    def build_skill_system_prompts(context: nil)
      skill_query = agent_skills.where(is_active: true)
        .joins(:skill)
        .where(ai_skills: { status: "active", is_enabled: true })
        .order("ai_agent_skills.priority ASC")

      # In workspace context, only inject skills tagged with "workspace" to reduce prompt bloat
      if context == :workspace
        skill_query = skill_query.where("ai_skills.tags @> ?", '["workspace"]')
      end

      skill_data = skill_query.pluck("ai_skills.slug", "ai_skills.system_prompt")

      injected_slugs = skill_data.reject { |_slug, prompt| prompt.blank? }.map(&:first)
      if injected_slugs.any?
        Rails.logger.info("[Ai::Agent] #{name}: injecting #{injected_slugs.size} skill prompts: #{injected_slugs.join(', ')}")
      else
        Rails.logger.info("[Ai::Agent] #{name}: no skill prompts to inject (#{skill_data.size} skills matched, all prompts blank)")
      end

      skill_data.map(&:last).reject(&:blank?).join("\n\n")
    end

    # Auto-resolve provider when model name changes to a different provider family
    def auto_resolve_provider_from_model
      model_name = mcp_metadata.dig("model_config", "model")
      return if model_name.blank?

      target_type = provider_type_for_model(model_name)
      return if target_type.nil? || (provider.present? && provider.provider_type == target_type)

      resolved = account.ai_providers.active.by_type(target_type).ordered_by_priority.first
      if resolved
        self.provider = resolved
        Rails.logger.info("[Ai::Agent] Auto-resolved provider for model '#{model_name}': #{resolved.name} (#{target_type})")
      else
        errors.add(:base, "No active #{target_type} provider found in account for model '#{model_name}'")
      end
    end

    # Map model name prefix to provider_type
    def provider_type_for_model(model_name)
      case model_name
      when /\Aclaude/   then "anthropic"
      when /\Agrok/     then "grok"
      when /\Agpt-|\Ao[134]/ then "openai"
      when /\Agemini/   then "google"
      when /\Amistral/  then "mistral"
      else nil # Unknown models: leave provider unchanged (ollama/custom stay as-is)
      end
    end

    # Prevent model/provider mismatches (e.g. grok-3 on Anthropic provider)
    def model_matches_provider
      model = mcp_metadata.dig("model_config", "model")
      return if model.blank?

      ptype = provider.provider_type
      valid = case ptype
              when "anthropic" then model.start_with?("claude")
              when "openai" then !model.start_with?("claude", "grok")
              when "grok" then model.start_with?("grok")
              when "ollama" then true
              else true
              end

      unless valid
        supported = provider.supported_models.map { |m| m["id"] || m["name"] }.compact.first(5).join(", ")
        errors.add(:base, "Model '#{model}' is incompatible with #{ptype} provider. Supported: #{supported}")
      end
    end

    # Warn when model capability doesn't match agent type requirements.
    # Lightweight models (mini/haiku/small) are fine for assistants and workers,
    # but monitor and data_analyst roles benefit from stronger reasoning models.
    # (Tier data + classification live in Ai::ModelTiers.)

    # Agent types that benefit from stronger models
    REASONING_PREFERRED_TYPES = %w[monitor data_analyst].freeze

    def model_suitable_for_agent_type
      model = mcp_metadata.dig("model_config", "model")
      return if model.blank? || agent_type.blank?
      return unless REASONING_PREFERRED_TYPES.include?(agent_type)

      tier = ::Ai::ModelTiers.classify(model)
      return unless tier == :light

      Rails.logger.warn(
        "[Ai::Agent] Agent '#{name}' (#{agent_type}) uses lightweight model '#{model}'. " \
        "Consider a standard or reasoning-tier model for better #{agent_type} performance."
      )
    end

    def sync_to_knowledge_graph
      return unless account_id.present?

      Ai::SkillGraph::BridgeService.new(account).sync_agent(self)
    rescue StandardError => e
      Rails.logger.warn "[Ai::Agent] KG sync failed for agent #{id}: #{e.message}"
    end

    def notify_mcp_resources_changed
      ::Mcp::SessionNotifier.notify_resources_changed(account)
    rescue StandardError => e
      Rails.logger.warn "[Ai::Agent] MCP resource notification failed: #{e.message}"
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

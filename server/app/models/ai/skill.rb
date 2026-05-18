# frozen_string_literal: true

module Ai
  class Skill < ApplicationRecord
    self.table_name = "ai_skills"

    # ==========================================
    # Constants
    # ==========================================
    CATEGORIES = %w[
      productivity sales customer_support product_management marketing
      legal finance data business_search bio_research skill_management
      code_intelligence testing_qa devops security sre_observability
      database_ops release_management research documentation trading
    ].freeze

    STATUSES = %w[active inactive draft].freeze

    # Metadata keys that affect the ConciergeRouter's routing decisions
    # (which agent handles a query, whether to delegate vs. invoke directly).
    # Changes to these fields trigger an auto version bump so the audit
    # trail captures behavior-affecting edits, not just casual metadata
    # tweaks like icon or author.
    ROUTING_METADATA_FIELDS = %w[domain invocation_mode].freeze

    # Two-value taxonomy that drives the invoke-vs-delegate decision.
    # Binary on purpose — a sliding "complexity" scale invites endless
    # debate without affecting routing.
    INVOCATION_MODES = %w[one_shot workflow_step].freeze

    # Per-process registry of domain → executor-namespace pattern,
    # populated by extension engines in their after_initialize hooks. The
    # parent platform has zero compile-time knowledge of which extensions
    # exist — extensions opt themselves in via Ai::Skill.register_domain.
    # "platform" is the always-present built-in domain (Powernode Assistant's
    # native skills); extension domains map to specialist agents whose
    # `autonomy_config["extension"]` matches the domain value.
    @domain_registry = { "platform" => nil }
    @domain_registry_mutex = Mutex.new

    class << self
      attr_reader :domain_registry
    end

    # Extension engines call this in an after_initialize block to register
    # their routing domain. Idempotent — re-registering the same name
    # with the same pattern is a no-op. Thread-safe (initializer order
    # can interleave with first request handling on boot).
    #
    #   Ai::Skill.register_domain(
    #     name: "system",
    #     executor_namespace_pattern: /\ASystem::/
    #   )
    def self.register_domain(name:, executor_namespace_pattern: nil)
      @domain_registry_mutex.synchronize do
        @domain_registry[name.to_s] = executor_namespace_pattern
      end
    end

    def self.registered_domains
      @domain_registry_mutex.synchronize { @domain_registry.keys.dup }
    end

    # ==========================================
    # Associations
    # ==========================================
    belongs_to :account, optional: true
    belongs_to :knowledge_base, class_name: "Ai::KnowledgeBase",
               foreign_key: "ai_knowledge_base_id", optional: true
    has_and_belongs_to_many :mcp_servers,
                            join_table: "ai_skills_mcp_servers",
                            foreign_key: "ai_skill_id"
    belongs_to :parent_skill, class_name: "Ai::Skill", foreign_key: "parent_skill_id", optional: true
    has_many :child_skills, class_name: "Ai::Skill", foreign_key: "parent_skill_id", dependent: :nullify
    has_many :agent_skills, class_name: "Ai::AgentSkill", foreign_key: "ai_skill_id", dependent: :destroy
    has_many :agents, class_name: "Ai::Agent", through: :agent_skills, source: :agent
    has_one :knowledge_graph_node, class_name: "Ai::KnowledgeGraphNode", foreign_key: "ai_skill_id", dependent: :nullify
    has_many :versions, class_name: "Ai::SkillVersion", foreign_key: "ai_skill_id", dependent: :destroy
    has_many :usage_records, class_name: "Ai::SkillUsageRecord", foreign_key: "ai_skill_id", dependent: :destroy
    has_many :proposals, class_name: "Ai::SkillProposal", foreign_key: "created_skill_id", dependent: :nullify
    has_many :conflicts_as_a, class_name: "Ai::SkillConflict", foreign_key: "skill_a_id", dependent: :destroy
    has_many :conflicts_as_b, class_name: "Ai::SkillConflict", foreign_key: "skill_b_id", dependent: :nullify
    has_many :compositions_as_composite, class_name: "Ai::SkillComposition", foreign_key: "composite_skill_id", dependent: :destroy
    has_many :component_skills, through: :compositions_as_composite, source: :component_skill
    has_many :compositions_as_component, class_name: "Ai::SkillComposition", foreign_key: "component_skill_id", dependent: :nullify
    has_many :recipe_runs, class_name: "Ai::SkillRecipeRun", foreign_key: "ai_skill_id", dependent: :destroy

    # ==========================================
    # Validations
    # ==========================================
    validates :name, presence: true, uniqueness: { scope: :account_id }
    validates :slug, presence: true, uniqueness: true
    validates :category, presence: true, inclusion: { in: CATEGORIES }
    validates :status, inclusion: { in: STATUSES }

    # ==========================================
    # Scopes
    # ==========================================
    scope :system_skills, -> { where(is_system: true) }
    scope :for_account, ->(account_id) { where(account_id: [account_id, nil]) }
    scope :by_category, ->(cat) { where(category: cat) }
    scope :active, -> { where(status: "active") }
    scope :enabled, -> { where(is_enabled: true) }

    # Routing scopes — used by ConciergeRouter to pre-filter candidates
    # before similarity ranking.
    scope :for_domain, ->(domain) { where("metadata->>'domain' = ?", domain.to_s) }
    scope :one_shot, -> { where("metadata->>'invocation_mode' = ?", "one_shot") }
    scope :workflow_step, -> { where("metadata->>'invocation_mode' = ?", "workflow_step") }

    # Recipe skills — skills whose behavior is defined by a declarative
    # ordered list of MCP tool invocations stored in metadata["recipe"]
    # rather than a Ruby executor class. Dispatched by Ai::SkillRecipeRunner.
    scope :recipe_skills, -> { where("metadata ? 'recipe'") }

    # ==========================================
    # Callbacks
    # ==========================================
    before_validation :generate_slug, on: :create
    before_update :bump_version_on_routing_change
    after_commit :sync_to_knowledge_graph, on: [:create, :update]
    after_commit :enqueue_conflict_check, on: [:create, :update], if: :conflict_relevant_change?
    after_destroy :archive_knowledge_graph_node

    # ==========================================
    # Public Methods
    # ==========================================

    def skill_summary
      {
        id: id,
        name: name,
        slug: slug,
        description: description,
        category: category,
        status: status,
        is_system: is_system,
        is_enabled: is_enabled,
        command_count: commands&.size || 0,
        connector_count: mcp_servers.size,
        has_knowledge_base: ai_knowledge_base_id.present?,
        tags: tags,
        usage_count: usage_count,
        version: version
      }
    end

    def skill_details
      skill_summary.merge(
        system_prompt: system_prompt,
        commands: commands,
        activation_rules: activation_rules,
        metadata: metadata,
        knowledge_base: knowledge_base ? { id: knowledge_base.id, name: knowledge_base.name } : nil,
        connectors: mcp_servers.map { |s| { id: s.id, name: s.name, status: s.status } },
        created_at: created_at,
        updated_at: updated_at
      )
    end

    def command_definitions
      commands || []
    end

    def activate!
      update!(is_enabled: true)
    end

    def deactivate!
      update!(is_enabled: false)
    end

    def record_usage!(outcome:, agent: nil, duration_ms: nil, execution_id: nil, execution_type: nil)
      usage_records.create!(
        account: account,
        ai_agent_id: agent&.id,
        outcome: outcome,
        duration_ms: duration_ms,
        execution_id: execution_id,
        execution_type: execution_type
      )

      increment!(:usage_count)

      if outcome == "success"
        increment!(:positive_usage_count)
      else
        increment!(:negative_usage_count)
      end

      update!(last_used_at: Time.current)
      recalculate_effectiveness! if (positive_usage_count + negative_usage_count) >= 5
    end

    def recalculate_effectiveness!
      kg_confidence = knowledge_graph_node&.confidence || 0.5
      usage_rate = usage_success_rate
      learning_eff = compound_learning_effectiveness

      score = (0.3 * kg_confidence + 0.5 * usage_rate + 0.2 * learning_eff).round(4)
      update!(effectiveness_score: score)
    end

    def usage_success_rate
      total = positive_usage_count + negative_usage_count
      return 0.5 if total.zero?

      (positive_usage_count.to_f / total).round(4)
    end

    def composite?
      is_composite == true
    end

    def active_conflicts
      Ai::SkillConflict.where(status: %w[detected reviewing])
        .where("skill_a_id = :id OR skill_b_id = :id", id: id)
    end

    # === Routing accessors (ConciergeRouter) ===

    # Returns the skill's routing domain. Explicit `metadata["domain"]` wins;
    # otherwise inferred from the executor namespace as a safety net for
    # skills registered before the metadata model existed.
    def domain
      explicit = metadata.is_a?(Hash) ? metadata["domain"] : nil
      return explicit if explicit.present?

      infer_domain_from_executor
    end

    # Returns "one_shot" or "workflow_step". Defaults to "one_shot" for
    # skills registered before the metadata model — most skills are
    # one-shot, so this is the safer default.
    def invocation_mode
      mode = metadata.is_a?(Hash) ? metadata["invocation_mode"] : nil
      INVOCATION_MODES.include?(mode) ? mode : "one_shot"
    end

    def one_shot?
      invocation_mode == "one_shot"
    end

    def workflow_step?
      invocation_mode == "workflow_step"
    end

    # === Recipe skill predicates ======================================
    #
    # A recipe skill has `metadata["recipe"]` populated (per the schema in
    # docs/concepts/agents-and-autonomy.md §"Recipe specification").
    # Recipe skills are dispatched by Ai::SkillRecipeRunner rather than a
    # Ruby executor class — the metadata is the executable artifact.

    def recipe?
      metadata.is_a?(Hash) && metadata["recipe"].is_a?(Hash)
    end

    def recipe
      return nil unless recipe?

      metadata["recipe"]
    end

    def recipe_inputs
      return [] unless recipe?

      Array(recipe["inputs"])
    end

    def recipe_steps
      return [] unless recipe?

      Array(recipe["steps"])
    end

    # Returns the canonical chat-facing specialist this skill should
    # delegate to (or nil for platform-domain skills that the router
    # invokes directly). Tiebreaker chain:
    #
    #   1. Among AgentSkill bindings, keep only agent_type="assistant"
    #      (monitors like Fleet Autonomy aren't conversation participants).
    #   2. Prefer the agent whose own `autonomy_config["extension"]`
    #      matches this skill's domain (semantic affinity).
    #   3. Prefer the highest-priority AgentSkill binding (lowest integer).
    #   4. Earliest created_at — deterministic last-resort.
    def specialist_agent
      return nil if domain == "platform"

      candidates = agent_skills.includes(:agent)
                               .map(&:agent)
                               .compact
                               .select { |a| a.agent_type == "assistant" }
      return nil if candidates.empty?
      return candidates.first if candidates.one?

      # Tiebreak 1: domain affinity
      affinity = candidates.find { |a| a.autonomy_config.is_a?(Hash) && a.autonomy_config["extension"] == domain }
      return affinity if affinity

      # Tiebreak 2: AgentSkill priority (lower = higher priority, per existing convention)
      candidate_ids = candidates.map(&:id)
      best_binding = agent_skills.where(ai_agent_id: candidate_ids).order(:priority).first
      return ::Ai::Agent.find_by(id: best_binding.ai_agent_id) if best_binding

      # Tiebreak 3: deterministic — earliest binding wins
      earliest = agent_skills.where(ai_agent_id: candidate_ids).order(:created_at).first
      ::Ai::Agent.find_by(id: earliest.ai_agent_id)
    end

    private

    def sync_to_knowledge_graph
      return unless account_id.present?

      Ai::SkillGraph::BridgeService.new(Account.find(account_id)).sync_skill(self)
    rescue StandardError => e
      Rails.logger.warn "[Ai::Skill] KG sync failed for skill #{id}: #{e.message}"
    end

    def conflict_relevant_change?
      # New records always need a conflict check
      return true if id_previously_changed?

      # Only enqueue when columns that affect conflict detection change
      conflict_columns = %w[name description slug category system_prompt commands tags status]
      (saved_changes.keys & conflict_columns).any?
    end

    def enqueue_conflict_check
      WorkerJobService.enqueue_ai_skill_conflict_check(id)
    rescue StandardError => e
      Rails.logger.warn "[Ai::Skill] Conflict check enqueue failed for skill #{id}: #{e.message}"
    end

    def archive_knowledge_graph_node
      knowledge_graph_node&.archive!
    rescue StandardError => e
      Rails.logger.warn "[Ai::Skill] KG archive failed for skill #{id}: #{e.message}"
    end

    def generate_slug
      return if slug.present?

      base_slug = name.to_s.parameterize
      self.slug = base_slug

      counter = 1
      while self.class.exists?(slug: self.slug)
        self.slug = "#{base_slug}-#{counter}"
        counter += 1
      end
    end

    def compound_learning_effectiveness
      return 0.5 unless account_id.present?

      learnings = Ai::CompoundLearning.active.for_account(account_id)
                    .where("tags @> ?", [slug].to_json)
      return 0.5 if learnings.empty?

      learnings.average(:effectiveness_score)&.to_f || 0.5
    end

    # Auto-bumps the minor version when a routing-relevant metadata field
    # changes. Triggered by before_update so updates flowing through the
    # ORM (seeds, MCP update_skill calls, admin UI edits) all get the
    # bump consistently. Idempotent — re-saving with the same metadata
    # doesn't bump.
    def bump_version_on_routing_change
      return unless metadata_changed?

      previous = metadata_was || {}
      current  = metadata     || {}
      changed  = ROUTING_METADATA_FIELDS.any? { |field| previous[field] != current[field] }
      return unless changed

      self.version = next_minor_version(version)
    end

    # Inferred domain fallback. Walks the runtime domain registry —
    # extensions register their executor-namespace pattern via
    # Ai::Skill.register_domain, the parent has no compile-time knowledge
    # of which extensions exist. Used only when metadata["domain"] is
    # absent. Defaults to "platform" when no pattern matches.
    def infer_domain_from_executor
      executor = metadata.is_a?(Hash) ? metadata["executor_class"].to_s : ""
      return "platform" if executor.empty?

      self.class.domain_registry.each do |domain, pattern|
        next if pattern.nil?
        return domain if executor.match?(pattern)
      end
      "platform"
    end

    # Semver-style minor bump: 1.2.3 → 1.3.0. Defaults missing version
    # to "1.0.0" so freshly-seeded skills get a stable starting point.
    def next_minor_version(current)
      parts = (current.to_s.split(".") + %w[0 0 0]).first(3).map(&:to_i)
      parts[1] += 1
      parts[2] = 0
      parts.join(".")
    end
  end
end

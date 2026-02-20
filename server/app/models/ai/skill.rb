# frozen_string_literal: true

module Ai
  class Skill < ApplicationRecord
    self.table_name = "ai_skills"

    # ==========================================
    # Constants
    # ==========================================
    CATEGORIES = %w[
      productivity sales customer_support product_management marketing
      legal finance data enterprise_search bio_research skill_management
      code_intelligence testing_qa devops security sre_observability
      database_ops release_management research documentation
    ].freeze

    STATUSES = %w[active inactive draft].freeze

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

    # ==========================================
    # Callbacks
    # ==========================================
    before_validation :generate_slug, on: :create
    after_commit :sync_to_knowledge_graph, on: [:create, :update]
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

    def increment_usage!
      increment!(:usage_count)
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

    def active_conflicts
      Ai::SkillConflict.where(status: %w[detected reviewing])
        .where("skill_a_id = :id OR skill_b_id = :id", id: id)
    end

    private

    def sync_to_knowledge_graph
      return unless account_id.present?

      Ai::SkillGraph::BridgeService.new(Account.find(account_id)).sync_skill(self)
    rescue StandardError => e
      Rails.logger.warn "[Ai::Skill] KG sync failed for skill #{id}: #{e.message}"
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
  end
end

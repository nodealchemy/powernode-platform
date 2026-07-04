# frozen_string_literal: true

module Ai
  class CompoundLearning < ApplicationRecord
    self.table_name = "ai_compound_learnings"

    has_neighbors :embedding

    # ==========================================
    # Constants
    # ==========================================
    CATEGORIES = %w[pattern anti_pattern best_practice discovery fact failure_mode review_finding performance_insight reflexion].freeze
    SCOPES = %w[team global].freeze
    STATUSES = %w[active deprecated superseded verified disproven retired].freeze
    EXTRACTION_METHODS = %w[marker auto_success auto_failure review evaluation reflexion ralph_loop].freeze

    # ==========================================
    # Associations
    # ==========================================
    belongs_to :account
    belongs_to :ai_agent_team, class_name: "Ai::AgentTeam", foreign_key: "ai_agent_team_id", optional: true
    belongs_to :source_agent, class_name: "Ai::Agent", foreign_key: "source_agent_id", optional: true
    belongs_to :source_execution, class_name: "Ai::TeamExecution", foreign_key: "source_execution_id", optional: true
    belongs_to :superseded_by, class_name: "Ai::CompoundLearning", foreign_key: "superseded_by_id", optional: true
    belongs_to :verified_by, class_name: "User", foreign_key: "verified_by_id", optional: true
    belongs_to :disproven_by, class_name: "User", foreign_key: "disproven_by_id", optional: true
    # Portability (Tier-2): optional repo scoping for uncontaminated per-project recall
    belongs_to :git_repository, class_name: "Devops::GitRepository", foreign_key: "git_repository_id", optional: true

    has_many :superseding, class_name: "Ai::CompoundLearning", foreign_key: :superseded_by_id

    # ==========================================
    # Validations
    # ==========================================
    validates :category, presence: true, inclusion: { in: CATEGORIES }
    validates :scope, inclusion: { in: SCOPES }
    validates :status, inclusion: { in: STATUSES }
    validates :content, presence: true
    validates :importance_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
    validates :confidence_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }

    # ==========================================
    # Callbacks
    # ==========================================
    after_commit :enqueue_promotion_check, if: :promotion_threshold_crossed?
    after_commit :enqueue_graph_update_on_status_change, if: :saved_change_to_status?

    # ==========================================
    # Scopes
    # ==========================================
    scope :active, -> { where(status: "active") }
    scope :for_team, ->(team_id) { where(ai_agent_team_id: team_id) }
    scope :for_account, ->(account_id) { where(account_id: account_id) }
    # Portability (Tier-2): account + repository scoped recall
    scope :for_account_and_repo, ->(account_id, repository_id) { where(account_id: account_id, git_repository_id: repository_id) }
    scope :global_scope, -> { where(scope: "global") }
    scope :team_scope, -> { where(scope: "team") }
    scope :by_category, ->(cat) { where(category: cat) }
    scope :high_importance, -> { where("importance_score >= ?", 0.7) }
    scope :verified, -> { where(status: "verified") }
    scope :disproven, -> { where(status: "disproven") }
    scope :retired, -> { where(status: "retired") }
    scope :with_tag, ->(tag) { where("tags @> ?", [tag].to_json) }
    # Domain retirement seam: a learning belongs to a domain via either tags
    # (the field every extraction path actually populates today) or
    # applicable_domains (the purpose-built, GIN-indexed column that promotion
    # copies through but nothing currently writes) — match either so the seam
    # keeps working if callers migrate to applicable_domains later.
    scope :in_domain, ->(domain) { where("tags @> ? OR applicable_domains @> ?", [domain].to_json, [domain].to_json) }
    scope :with_embedding, -> { where.not(embedding: nil) }
    scope :recent, -> { order(created_at: :desc) }
    scope :by_effectiveness, -> { order(effectiveness_score: :desc) }

    # ==========================================
    # Class Methods
    # ==========================================

    # Semantic search using neighbor gem's nearest_neighbors scope (cosine distance)
    def self.semantic_search(query_embedding, account_id:, threshold: 0.6, limit: 20, repository_id: nil)
      return [] if query_embedding.blank?

      scope = where(account_id: account_id, status: %w[active verified])
      scope = scope.where(git_repository_id: repository_id) if repository_id.present?
      scope
        .nearest_neighbors(:embedding, query_embedding, distance: "cosine")
        .limit(limit)
        .to_a
        .select { |e| e.neighbor_distance <= 1.0 - threshold }
    end

    # Find near-duplicates by embedding similarity.
    # Returns a plain Array (not an ActiveRecord::Relation) — the post-filter
    # on neighbor_distance requires materializing the nearest_neighbors scope
    # first. Callers must not chain relation methods (.where, .or, a scope,
    # etc.) onto the result; use Array#select/#reject instead.
    def self.find_similar(embedding, account_id:, threshold: 0.92, limit: 5)
      return [] if embedding.blank?

      active.where(account_id: account_id)
        .nearest_neighbors(:embedding, embedding, distance: "cosine")
        .limit(limit)
        .to_a
        .select { |e| e.neighbor_distance <= 1.0 - threshold }
    end

    # ==========================================
    # Instance Methods
    # ==========================================

    # Blended importance that incorporates effectiveness feedback
    def effective_importance
      return importance_score if injection_count < 5

      smoothed = (positive_outcome_count + 2).to_f / (injection_count + 4)
      (importance_score * 0.3 + smoothed * 0.7).round(4)
    end

    # Age based on created_at (immutable) — not updated_at (reset by decay runs)
    def age_in_days
      ((Time.current - created_at) / 1.day).to_f
    end

    def boost_importance!(amount = 0.05)
      new_score = [importance_score + amount, 1.0].min
      update!(importance_score: new_score)
    end

    def decay_importance!
      return if decay_rate.zero?

      days_since = ((Time.current - updated_at) / 1.day).to_i
      return if days_since < 1

      decayed = importance_score * ((1 - decay_rate) ** days_since)
      update!(importance_score: [decayed, 0.05].max)
    end

    def record_injection_outcome!(successful:)
      increment!(:injection_count)
      if successful
        increment!(:positive_outcome_count)
      else
        increment!(:negative_outcome_count)
      end
      update!(last_injected_at: Time.current)
      recalculate_effectiveness!
      touch_event_processed!
    end

    # Neutral injection recorded at recall time (context injection). Counts the
    # injection immediately; the outcome resolves later — positively via
    # record_positive_outcome! when the consuming execution succeeds, or stays
    # unresolved (which correctly depresses effectiveness for learnings that get
    # injected but never credited).
    def record_injection!
      increment!(:injection_count)
      update!(last_injected_at: Time.current)
      recalculate_effectiveness!
      touch_event_processed!
    end

    # Resolve a previously recorded (neutral) injection as positive. Does NOT
    # bump injection_count — the injection was already counted at recall, unlike
    # record_injection_outcome! which records an injection+outcome pair at once.
    def record_positive_outcome!
      increment!(:positive_outcome_count)
      recalculate_effectiveness!
      touch_event_processed!
    end

    # Deliberately NOT increment!(:access_count) — increment! goes through
    # update_counters (raw SQL, no save, no dirty tracking), which silently
    # defeats the after_commit :enqueue_promotion_check callback below (it
    # depends on saved_change_to_access_count?). with_lock keeps the
    # read-modify-write atomic (row-locked) while still routing through
    # save!, so dirty tracking — and the promotion callback — actually fire.
    def record_access!
      with_lock do
        self.access_count += 1
        save!
      end
    end

    def touch_event_processed!
      update_column(:last_event_processed_at, Time.current)
    end

    # user: optional (nil for the scheduled heuristic pass — see
    # Ai::Learning::CompoundLearningService#verify_unverified_batch, which has
    # no human actor to attribute the attestation to). Human/agent-directed
    # verification via Ai::Tools::KnowledgeQualityTool always passes a real user.
    def verify!(user: nil)
      update!(
        status: "verified",
        verified_at: Time.current,
        verified_by_id: user&.id
      )
      boost_importance!(0.15)
      update!(confidence_score: [confidence_score + 0.1, 1.0].min)
      touch_event_processed!
    end

    # user: optional — see #verify! above.
    def disprove!(user: nil, reason:)
      update!(
        status: "disproven",
        disproven_at: Time.current,
        disproven_by_id: user&.id,
        contradiction_note: reason,
        importance_score: 0.05,
        confidence_score: 0.1
      )
      touch_event_processed!
    end

    def resolve_contradiction!(note:)
      update!(
        contradiction_resolved_at: Time.current,
        contradiction_note: note
      )
    end

    def supersede!(new_learning)
      update!(status: "superseded", superseded_by: new_learning)
    end

    # Cross-model variant of #supersede! for the learning-to-skill-promotion
    # campaign (P3): the target is an Ai::Skill, not another CompoundLearning,
    # so it can't go through the superseded_by association (FK'd to
    # ai_compound_learnings) — recorded in metadata instead, migration-free,
    # same convention as #retire!'s retired_domain/retired_reason. Idempotent:
    # a learning already superseded (by either path) is left alone rather
    # than re-pointed at a later skill — e.g. a learning shared by two
    # clusters that both get approved keeps its FIRST supersession.
    def supersede_by_skill!(skill)
      return if status == "superseded"

      update!(
        status: "superseded",
        metadata: metadata.merge(
          "superseded_by_skill_id" => skill.id,
          "superseded_reason" => "learning_to_skill_promotion",
          "superseded_at" => Time.current.iso8601
        )
      )
      touch_event_processed!
    end

    # Soft-retire: excludes the learning from every surfacing path (all of
    # which scope to status active/verified — see .active, .semantic_search,
    # .find_similar) without hard-deleting it. Retired rows stay queryable for
    # audit via list_learnings(status: "retired"). Domain/reason are recorded
    # in metadata rather than new columns to keep this migration-free.
    def retire!(domain: nil, reason: nil)
      update!(
        status: "retired",
        metadata: metadata.merge(
          "retired_domain" => domain,
          "retired_reason" => reason,
          "retired_at" => Time.current.iso8601
        ).compact
      )
      touch_event_processed!
    end

    def deprecate!
      update!(status: "deprecated")
    end

    def learning_summary
      {
        id: id,
        category: category,
        title: title,
        content: content,
        importance_score: importance_score,
        confidence_score: confidence_score,
        effectiveness_score: effectiveness_score,
        effective_importance: effective_importance,
        injection_count: injection_count,
        positive_outcome_count: positive_outcome_count,
        negative_outcome_count: negative_outcome_count,
        access_count: access_count,
        status: status,
        scope: scope,
        tags: tags,
        extraction_method: extraction_method,
        source_execution_successful: source_execution_successful,
        ai_agent_team_id: ai_agent_team_id,
        source_agent_id: source_agent_id,
        verified_at: verified_at&.iso8601,
        disproven_at: disproven_at&.iso8601,
        contradiction_note: contradiction_note,
        promoted_at: promoted_at&.iso8601,
        last_injected_at: last_injected_at&.iso8601,
        created_at: created_at&.iso8601,
        updated_at: updated_at&.iso8601
      }
    end

    private

    def promotion_threshold_crossed?
      saved_change_to_access_count? && access_count >= 2 && access_count_before_last_save.to_i < 2 && scope == "team"
    end

    def enqueue_promotion_check
      WorkerJobService.enqueue_ai_promote_learning(id)
    rescue StandardError => e
      Rails.logger.warn("[CompoundLearning] Failed to enqueue promotion: #{e.message}")
    end

    def enqueue_graph_update_on_status_change
      return unless status.in?(%w[verified disproven])

      # Find linked KG nodes and trigger recalculation
      nodes = Ai::KnowledgeGraphNode.where(account_id: account_id)
        .where("properties->>'source_learning_id' = ?", id)
      nodes.find_each do |node|
        WorkerJobService.enqueue_ai_update_graph_node(node.id)
      rescue StandardError => e
        Rails.logger.warn("[CompoundLearning] Failed to enqueue graph update for node #{node.id}: #{e.message}")
      end
    end

    def recalculate_effectiveness!
      return unless injection_count >= 3

      score = positive_outcome_count.to_f / injection_count
      update!(effectiveness_score: score.round(4))
    end
  end
end

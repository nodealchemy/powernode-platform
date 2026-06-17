# frozen_string_literal: true

module Ai
  class SharedKnowledge < ApplicationRecord
    self.table_name = "ai_shared_knowledges"

    has_neighbors :embedding

    # ==========================================
    # Constants
    # ==========================================
    CONTENT_TYPES = %w[text markdown code snippet procedure reference fact definition guide].freeze
    ACCESS_LEVELS = %w[private team account global].freeze
    SOURCE_TYPES = %w[agent workflow extraction manual import].freeze

    # ==========================================
    # Associations
    # ==========================================
    belongs_to :account
    belongs_to :created_by, class_name: "User", foreign_key: "created_by_id", optional: true
    # Portability (Tier-2): optional repo scoping for uncontaminated per-project recall
    belongs_to :git_repository, class_name: "Devops::GitRepository", foreign_key: "git_repository_id", optional: true

    # ==========================================
    # Validations
    # ==========================================
    validates :title, presence: true, length: { maximum: 500 }
    validates :content, presence: true
    validates :content_type, inclusion: { in: CONTENT_TYPES }
    validates :access_level, inclusion: { in: ACCESS_LEVELS }
    validates :quality_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }, allow_nil: true

    # ==========================================
    # Scopes
    # ==========================================
    scope :accessible_by, ->(access_level) {
      case access_level
      when "global" then where(access_level: "global")
      when "account" then where(access_level: %w[account global])
      when "team" then where(access_level: %w[team account global])
      else where(access_level: %w[private team account global])
      end
    }
    scope :by_content_type, ->(type) { where(content_type: type) }
    scope :with_tag, ->(tag) { where("? = ANY(tags)", tag) }
    scope :with_any_tags, ->(tags) { where("tags && ARRAY[?]::varchar[]", tags) }
    scope :with_embedding, -> { where.not(embedding: nil) }
    scope :high_quality, -> { where("quality_score >= ?", 0.7) }
    scope :recent, -> { order(created_at: :desc) }
    scope :frequently_used, -> { order(usage_count: :desc) }
    scope :by_source, ->(type) { where(source_type: type) }
    # Portability (Tier-2): account + repository scoped recall
    scope :for_account_and_repo, ->(account_id, repository_id) { where(account_id: account_id, git_repository_id: repository_id) }

    # ==========================================
    # Methods
    # ==========================================

    def touch_usage!
      update_columns(
        usage_count: usage_count + 1,
        last_used_at: Time.current,
        updated_at: Time.current
      )
      recalculate_quality_score! if usage_count % 5 == 0
    end

    def touch_event_processed!
      update_column(:last_event_processed_at, Time.current)
    end

    # Verify content integrity
    def verify_integrity!
      return true unless integrity_hash.present?

      computed = Digest::SHA256.hexdigest(content)
      computed == integrity_hash
    end

    # Compute and store integrity hash
    def compute_integrity_hash!
      update!(integrity_hash: Digest::SHA256.hexdigest(content))
    end

    # Search by semantic similarity
    def self.semantic_search(query_embedding, limit: 10, threshold: 0.7, repository_id: nil)
      distance_threshold = 1.0 - threshold
      scope = repository_id.present? ? where(git_repository_id: repository_id) : all
      scope.nearest_neighbors(:embedding, query_embedding, distance: "cosine")
        .limit(limit)
        .to_a
        .select { |e| e.neighbor_distance <= distance_threshold }
    end

    # Record an explicit 1-5 rating and trigger quality recalculation
    def record_rating!(score)
      score = score.to_i.clamp(1, 5)
      update!(rating_sum: rating_sum + score, rating_count: self.rating_count + 1)
      recalculate_quality_score!
      touch_event_processed!
      propagate_rating_to_source_learning!(score)
    end

    # Recalculate quality score using a weighted multi-factor formula
    def recalculate_quality_score!
      structural = calculate_structural_quality
      usage = calculate_usage_factor
      rating = calculate_rating_factor
      recency = calculate_recency_factor

      new_score = (
        structural * 0.30 +
        usage * 0.25 +
        rating * 0.25 +
        recency * 0.20
      ).round(4)

      update!(
        quality_score: [new_score, 1.0].min,
        last_quality_recalc_at: Time.current
      )
    end

    private

    def propagate_rating_to_source_learning!(score)
      source_id = provenance&.dig("source_learning_id") || provenance&.dig("original_learning_id")
      return unless source_id

      learning = Ai::CompoundLearning.find_by(id: source_id, account_id: account_id)
      return unless learning&.status&.in?(%w[active verified])

      if score >= 4
        learning.boost_importance!(0.03)
      elsif score <= 2
        learning.decay_importance!
      end
      learning.touch_event_processed!
    rescue StandardError => e
      Rails.logger.warn("[SharedKnowledge] Rating propagation failed: #{e.message}")
    end

    def calculate_structural_quality
      score = 0.3
      score += [content.to_s.length / 2000.0, 0.2].min
      score += 0.1 if content.to_s.match?(/^#+\s/m)
      score += 0.1 if content.to_s.match?(/^[-*]\s/m)
      score += 0.1 if content.to_s.match?(/```/)
      score += [tags.to_a.length * 0.03, 0.1].min
      [score, 1.0].min
    end

    def calculate_usage_factor
      return 0.1 if usage_count.zero?

      [Math.log10(usage_count + 1) / 3.0, 1.0].min
    end

    def calculate_rating_factor
      return 0.5 if rating_count.zero?

      avg = rating_sum.to_f / rating_count
      (avg - 1.0) / 4.0 # Normalize 1-5 to 0-1
    end

    def calculate_recency_factor
      return 0.8 if last_used_at.nil?

      days_ago = ((Time.current - last_used_at) / 1.day).to_f
      decayed = Math.exp(-0.01 * days_ago)
      [decayed, 0.2].max
    end
  end
end

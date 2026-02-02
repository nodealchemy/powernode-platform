# frozen_string_literal: true

module Ai
  class ContextEntry < ApplicationRecord
    # ==================== Concerns ====================
    include Auditable

    # ==================== Constants ====================
    ENTRY_TYPES = %w[fact memory preference knowledge tool_result observation insight].freeze
    SOURCE_TYPES = %w[user_input agent_output workflow import api system].freeze
    MEMORY_TYPES = %w[factual experiential working].freeze

    # ==================== Associations ====================
    belongs_to :persistent_context, class_name: "Ai::PersistentContext", foreign_key: "ai_persistent_context_id"
    belongs_to :created_by_user, class_name: "User", optional: true
    belongs_to :agent, class_name: "Ai::Agent", foreign_key: "ai_agent_id", optional: true
    belongs_to :previous_version, class_name: "Ai::ContextEntry", optional: true

    has_many :newer_versions, class_name: "Ai::ContextEntry", foreign_key: :previous_version_id, dependent: :nullify
    has_many :access_logs, class_name: "Ai::ContextAccessLog", foreign_key: "ai_context_entry_id", dependent: :destroy

    # ==================== Validations ====================
    validates :entry_key, presence: true, length: { maximum: 255 }
    validates :entry_key, uniqueness: { scope: :ai_persistent_context_id, conditions: -> { where(archived_at: nil) } }
    validates :content, presence: true
    validates :entry_type, inclusion: { in: ENTRY_TYPES }, allow_nil: true
    validates :source_type, inclusion: { in: SOURCE_TYPES }, allow_nil: true
    validates :memory_type, inclusion: { in: MEMORY_TYPES }, allow_nil: true
    validates :version, presence: true, numericality: { only_integer: true, greater_than: 0 }
    validates :importance_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }, allow_nil: true
    validates :confidence_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }, allow_nil: true

    # ==================== Scopes ====================
    scope :active, -> { where(archived_at: nil).where("ai_context_entries.expires_at IS NULL OR ai_context_entries.expires_at > ?", Time.current) }
    scope :archived, -> { where.not(archived_at: nil) }
    scope :expired, -> { where("expires_at <= ?", Time.current) }
    scope :by_type, ->(type) { where(entry_type: type) }
    scope :by_source, ->(source) { where(source_type: source) }
    scope :by_memory_type, ->(type) { where(memory_type: type) }
    scope :factual, -> { by_memory_type("factual") }
    scope :experiential, -> { by_memory_type("experiential") }
    scope :working, -> { by_memory_type("working") }
    scope :high_importance, -> { where("importance_score >= ?", 0.7) }
    scope :low_importance, -> { where("importance_score < ?", 0.3) }
    scope :high_confidence, -> { where("confidence_score >= ?", 0.8) }
    scope :by_agent, ->(agent_id) { where(ai_agent_id: agent_id) }
    scope :recent, -> { order(created_at: :desc) }
    scope :frequently_accessed, -> { order(access_count: :desc) }
    scope :searchable, -> { where.not(content_text: nil) }
    scope :successful_outcomes, -> { where(outcome_success: true) }
    scope :failed_outcomes, -> { where(outcome_success: false) }
    scope :with_tag, ->(tag) { where("context_tags @> ?", [ tag ].to_json) }
    scope :with_embedding, -> { where.not(embedding: nil) }

    # ==================== Callbacks ====================
    before_save :sanitize_jsonb_fields
    before_save :extract_searchable_text
    before_save :decay_relevance
    after_save :update_context_entry_count
    after_destroy :update_context_entry_count

    # ==================== Instance Methods ====================

    def entry_summary
      {
        id: id,
        entry_key: entry_key,
        entry_type: entry_type,
        memory_type: memory_type,
        importance_score: importance_score,
        confidence_score: confidence_score,
        version: version,
        created_at: created_at,
        last_accessed_at: last_accessed_at
      }
    end

    def entry_details
      entry_summary.merge(
        content: content,
        content_text: content_text,
        metadata: metadata,
        source_type: source_type,
        source_id: source_id,
        agent_id: ai_agent_id,
        access_count: access_count,
        expires_at: expires_at,
        archived_at: archived_at,
        previous_version_id: previous_version_id,
        context_tags: context_tags,
        task_context: task_context,
        outcome_success: outcome_success
      )
    end

    def entry_snapshot
      {
        entry_key: entry_key,
        entry_type: entry_type,
        memory_type: memory_type,
        content: content,
        content_text: content_text,
        metadata: metadata,
        importance_score: importance_score,
        confidence_score: confidence_score,
        source_type: source_type,
        source_id: source_id,
        context_tags: context_tags
      }
    end

    # Memory type helpers
    def factual?
      memory_type == "factual"
    end

    def experiential?
      memory_type == "experiential"
    end

    def working?
      memory_type == "working"
    end

    # Calculate effective relevance score combining importance, confidence, and recency
    def effective_relevance_score
      base_score = importance_score || 0.5
      confidence_factor = confidence_score || 1.0
      recency_factor = calculate_recency_factor

      (base_score * confidence_factor * recency_factor).round(4)
    end

    # Semantic similarity search using embeddings
    def self.semantic_search(query_embedding, agent_id: nil, memory_type: nil, limit: 10, threshold: 0.7)
      return none unless embedding_column_exists?

      scope = active.with_embedding
      scope = scope.by_agent(agent_id) if agent_id
      scope = scope.by_memory_type(memory_type) if memory_type

      # Use pgvector's cosine distance operator
      scope.select("*, 1 - (embedding <=> '#{query_embedding}') AS similarity")
           .where("1 - (embedding <=> '#{query_embedding}') >= ?", threshold)
           .order(Arel.sql("similarity DESC"))
           .limit(limit)
    end

    # Check if embedding column exists
    def self.embedding_column_exists?
      column_names.include?("embedding")
    end

    # Get embedding (from column or metadata)
    def embedding
      if self.class.embedding_column_exists?
        self[:embedding]
      else
        metadata&.dig("embedding")
      end
    end

    # Update embedding for this entry
    def update_embedding!(embedding_vector)
      if self.class.embedding_column_exists?
        update!(embedding: embedding_vector)
      else
        # Store in metadata if column doesn't exist
        update!(metadata: (metadata || {}).merge("embedding" => embedding_vector))
      end
    end

    def read_content
      touch(:last_accessed_at)
      increment!(:access_count)
      content
    end

    def update_content(new_content, create_version: true)
      if create_version && content != new_content
        # Archive this version first (to allow new entry with same key)
        update!(archived_at: Time.current)

        # Create a new version
        new_entry = persistent_context.context_entries.create!(
          entry_key: entry_key,
          entry_type: entry_type,
          content: new_content,
          metadata: metadata,
          importance_score: importance_score,
          source_type: source_type,
          source_id: source_id,
          ai_agent_id: ai_agent_id,
          previous_version_id: id,
          version: version + 1
        )

        new_entry
      else
        update!(content: new_content)
        self
      end
    end

    def archive!
      update!(archived_at: Time.current)
    end

    def unarchive!
      update!(archived_at: nil)
    end

    def archived?
      archived_at.present?
    end

    def expired?
      expires_at.present? && expires_at <= Time.current
    end

    def set_expiration(duration)
      update!(expires_at: Time.current + duration)
    end

    def boost_importance!(amount = 0.1)
      new_score = [ importance_score + amount, 1.0 ].min
      update!(importance_score: new_score)
    end

    def reduce_importance!(amount = 0.1)
      new_score = [ importance_score - amount, 0.0 ].max
      update!(importance_score: new_score)
    end

    def version_history
      versions = [ self ]
      current = self

      while current.previous_version.present?
        current = current.previous_version
        versions << current
      end

      versions.reverse
    end

    def latest_version
      newest = newer_versions.order(version: :desc).first
      newest&.latest_version || self
    end

    def is_latest_version?
      newer_versions.active.empty?
    end

    private

    def sanitize_jsonb_fields
      self.content = {} if content.blank?
      self.metadata = {} if metadata.blank?
    end

    def extract_searchable_text
      # Extract text content for full-text search
      text_parts = []

      if content.is_a?(Hash)
        text_parts << content["text"] if content["text"].present?
        text_parts << content["value"] if content["value"].present?
        text_parts << content["description"] if content["description"].present?
      elsif content.is_a?(String)
        text_parts << content
      end

      self.content_text = text_parts.join(" ").truncate(10_000) if text_parts.any?
    end

    def decay_relevance
      return unless relevance_decay_rate.present? && relevance_decay_rate > 0
      return unless last_relevance_update.present?

      days_since_update = (Time.current - last_relevance_update) / 1.day
      return if days_since_update < 1

      decay = relevance_decay_rate * days_since_update
      self.importance_score = [ importance_score - decay, 0.0 ].max
      self.last_relevance_update = Time.current
    end

    def update_context_entry_count
      persistent_context.update_column(:entry_count, persistent_context.context_entries.active.count)
    end

    def calculate_recency_factor
      return 1.0 unless last_accessed_at.present?

      days_since_access = (Time.current - last_accessed_at) / 1.day
      decay = decay_rate || 0.0

      # Exponential decay based on days since access
      Math.exp(-decay * days_since_access).round(4)
    end

    def sanitize_context_tags
      self.context_tags = [] if context_tags.blank?
      self.context_tags = context_tags.map(&:to_s).uniq.compact if context_tags.is_a?(Array)
    end
  end
end

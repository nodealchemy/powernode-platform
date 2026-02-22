# frozen_string_literal: true

module Ai
  class AgentShortTermMemory < ApplicationRecord
    self.table_name = "ai_agent_short_term_memories"

    # ==========================================
    # Constants
    # ==========================================
    MEMORY_TYPES = %w[general conversation tool_result observation plan state].freeze
    DEFAULT_TTL = 3600 # 1 hour

    # ==========================================
    # Associations
    # ==========================================
    belongs_to :account
    belongs_to :agent, class_name: "Ai::Agent", foreign_key: "agent_id"

    # ==========================================
    # Validations
    # ==========================================
    validates :session_id, presence: true
    validates :memory_key, presence: true
    validates :memory_value, presence: true
    validates :memory_type, inclusion: { in: MEMORY_TYPES }
    validates :memory_key, uniqueness: { scope: %i[agent_id session_id] }

    # ==========================================
    # Scopes
    # ==========================================
    scope :for_session, ->(session_id) { where(session_id: session_id) }
    scope :for_agent, ->(agent_id) { where(agent_id: agent_id) }
    scope :active, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }
    scope :expired, -> { where("expires_at IS NOT NULL AND expires_at <= ?", Time.current) }
    scope :by_type, ->(type) { where(memory_type: type) }
    scope :recent, -> { order(last_accessed_at: :desc, created_at: :desc) }
    scope :frequently_accessed, -> { order(access_count: :desc) }

    # ==========================================
    # Callbacks
    # ==========================================
    before_create :set_expiration
    after_commit :enqueue_consolidation_check, if: :consolidation_threshold_crossed?

    # ==========================================
    # Methods
    # ==========================================

    def expired?
      expires_at.present? && expires_at <= Time.current
    end

    def touch_access!
      update_columns(
        access_count: access_count + 1,
        last_accessed_at: Time.current
      )
    end

    def refresh_ttl!
      update_columns(expires_at: Time.current + ttl_seconds.seconds) if ttl_seconds.present?
    end

    # Cleanup expired memories
    def self.cleanup_expired!
      expired.delete_all
    end

    private

    def consolidation_threshold_crossed?
      saved_change_to_access_count? && access_count >= 3 && access_count_before_last_save.to_i < 3
    end

    def enqueue_consolidation_check
      WorkerJobService.enqueue_ai_consolidate_memory_entry(id)
    rescue StandardError => e
      Rails.logger.warn("[AgentShortTermMemory] Failed to enqueue consolidation: #{e.message}")
    end

    def set_expiration
      self.ttl_seconds ||= DEFAULT_TTL
      self.expires_at ||= Time.current + ttl_seconds.seconds
      self.last_accessed_at ||= Time.current
    end
  end
end

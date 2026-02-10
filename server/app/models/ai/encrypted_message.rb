# frozen_string_literal: true

module Ai
  class EncryptedMessage < ApplicationRecord
    self.table_name = "ai_encrypted_messages"

    # ==========================================
    # Constants
    # ==========================================
    STATUSES = %w[delivered read expired].freeze

    # ==========================================
    # Associations
    # ==========================================
    belongs_to :account

    # ==========================================
    # Validations
    # ==========================================
    validates :from_agent_id, presence: true
    validates :to_agent_id, presence: true
    validates :nonce, presence: true
    validates :ciphertext, presence: true
    validates :auth_tag, presence: true
    validates :sequence_number, presence: true,
              numericality: { only_integer: true, greater_than_or_equal_to: 0 },
              uniqueness: { scope: :session_id }
    validates :status, inclusion: { in: STATUSES }

    # ==========================================
    # Scopes
    # ==========================================
    scope :for_agent, ->(agent_id) { where(from_agent_id: agent_id).or(where(to_agent_id: agent_id)) }
    scope :from_agent, ->(agent_id) { where(from_agent_id: agent_id) }
    scope :to_agent, ->(agent_id) { where(to_agent_id: agent_id) }
    scope :for_session, ->(session_id) { where(session_id: session_id) }
    scope :for_task, ->(task_id) { where(task_id: task_id) }
    scope :recent, ->(duration = 24.hours) { where("created_at >= ?", duration.ago) }
    scope :by_sequence, -> { order(sequence_number: :asc) }
    scope :delivered, -> { where(status: "delivered") }
    scope :expired, -> { where(status: "expired") }

    # ==========================================
    # Methods
    # ==========================================
    def delivered?
      status == "delivered"
    end

    def read?
      status == "read"
    end

    def expired?
      status == "expired"
    end

    def mark_read!
      update!(status: "read")
    end

    def mark_expired!
      update!(status: "expired")
    end
  end
end

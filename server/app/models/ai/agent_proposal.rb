# frozen_string_literal: true

module Ai
  class AgentProposal < ApplicationRecord
    self.table_name = "ai_agent_proposals"

    PROPOSAL_TYPES = %w[
      feature knowledge_update code_change architecture
      process_improvement configuration sweep_execution
    ].freeze

    STATUSES = %w[pending_review approved rejected implemented withdrawn].freeze
    PRIORITIES = %w[low medium high critical].freeze

    # Associations
    belongs_to :account
    belongs_to :agent, class_name: "Ai::Agent", foreign_key: "ai_agent_id"
    belongs_to :target_user, class_name: "User", optional: true
    belongs_to :reviewed_by, class_name: "User", optional: true
    belongs_to :conversation, class_name: "Ai::Conversation", optional: true

    # Validations
    validates :title, presence: true, length: { maximum: 255 }
    validates :proposal_type, presence: true, inclusion: { in: PROPOSAL_TYPES }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :priority, presence: true, inclusion: { in: PRIORITIES }

    # JSON columns
    attribute :impact_assessment, :json, default: -> { {} }
    attribute :proposed_changes, :json, default: -> { {} }

    # Scopes
    scope :pending, -> { where(status: "pending_review") }
    scope :reviewed, -> { where(status: %w[approved rejected]) }
    scope :overdue, -> { pending.where("review_deadline < ?", Time.current) }
    scope :by_priority, -> { order(Arel.sql("CASE priority WHEN 'critical' THEN 0 WHEN 'high' THEN 1 WHEN 'medium' THEN 2 WHEN 'low' THEN 3 END")) }

    # Callbacks
    before_validation :set_review_deadline, on: :create

    def approve!(user)
      update!(
        status: "approved",
        reviewed_by: user,
        reviewed_at: Time.current
      )
    end

    def reject!(user)
      update!(
        status: "rejected",
        reviewed_by: user,
        reviewed_at: Time.current
      )
    end

    def withdraw!
      update!(status: "withdrawn")
    end

    def implement!
      update!(status: "implemented")
    end

    def pending?
      status == "pending_review"
    end

    def overdue?
      pending? && review_deadline.present? && review_deadline < Time.current
    end

    private

    def set_review_deadline
      self.review_deadline ||= 72.hours.from_now
    end
  end
end

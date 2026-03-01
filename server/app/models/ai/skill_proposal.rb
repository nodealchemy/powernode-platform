# frozen_string_literal: true

module Ai
  class SkillProposal < ApplicationRecord
    self.table_name = "ai_skill_proposals"

    # ==========================================
    # Constants
    # ==========================================
    STATUSES = %w[draft proposed approved created rejected].freeze

    # ==========================================
    # Associations
    # ==========================================
    belongs_to :account
    belongs_to :proposed_by_agent, class_name: "Ai::Agent", foreign_key: "proposed_by_agent_id", optional: true
    belongs_to :proposed_by_user, class_name: "User", foreign_key: "proposed_by_user_id", optional: true
    belongs_to :reviewed_by, class_name: "User", foreign_key: "reviewed_by_id", optional: true
    belongs_to :created_skill, class_name: "Ai::Skill", foreign_key: "created_skill_id", optional: true
    belongs_to :parent_proposal, class_name: "Ai::SkillProposal", foreign_key: "parent_proposal_id", optional: true
    has_many :child_proposals, class_name: "Ai::SkillProposal", foreign_key: "parent_proposal_id", dependent: :nullify

    # ==========================================
    # Validations
    # ==========================================
    validates :name, presence: true
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :category, inclusion: { in: Ai::Skill::CATEGORIES }, allow_nil: true

    # ==========================================
    # Scopes
    # ==========================================
    scope :active, -> { where.not(status: %w[rejected created]) }
    scope :pending_review, -> { where(status: "proposed") }
    scope :for_account, ->(account_id) { where(account_id: account_id) }
    scope :by_status, ->(status) { where(status: status) }

    # ==========================================
    # Callbacks
    # ==========================================
    before_validation :generate_slug, on: :create

    # ==========================================
    # State Transitions
    # ==========================================

    def submit!
      raise "Can only submit draft proposals" unless status == "draft"

      update!(status: "proposed", proposed_at: Time.current)
      auto_approve_if_eligible!
    end

    def approve!(reviewer)
      raise "Can only approve proposed proposals" unless status == "proposed"

      update!(status: "approved", reviewed_by: reviewer, reviewed_at: Time.current)
    end

    def reject!(reviewer, reason:)
      raise "Can only reject proposed proposals" unless status == "proposed"

      update!(status: "rejected", reviewed_by: reviewer, reviewed_at: Time.current, rejection_reason: reason)
    end

    def mark_created!(skill)
      raise "Can only create from approved proposals" unless status == "approved"

      update!(status: "created", created_skill: skill)
    end

    # ==========================================
    # Public Methods
    # ==========================================

    def can_auto_approve?
      trust_tier_at_proposal.in?(%w[trusted autonomous])
    end

    def proposal_summary
      {
        id: id,
        name: name,
        description: description,
        category: category,
        status: status,
        confidence_score: confidence_score,
        auto_approved: auto_approved,
        proposed_by_agent_id: proposed_by_agent_id,
        proposed_by_user_id: proposed_by_user_id,
        proposed_at: proposed_at,
        reviewed_at: reviewed_at,
        created_at: created_at
      }
    end

    private

    def auto_approve_if_eligible!
      return unless can_auto_approve?
      return unless Flipper.enabled?(:skill_lifecycle_auto_create)

      update!(status: "approved", auto_approved: true, reviewed_at: Time.current)
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
  end
end

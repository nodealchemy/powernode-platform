# frozen_string_literal: true

class CommunityAgentRating < ApplicationRecord
  # Concerns
  include Auditable

  # Associations
  belongs_to :community_agent
  belongs_to :account
  belongs_to :user
  belongs_to :a2a_task, class_name: "Ai::A2aTask", optional: true

  # Validations
  validates :rating, presence: true, inclusion: { in: 1..5 }
  validates :review, length: { maximum: 5000 }, allow_nil: true
  validate :one_rating_per_account

  # Scopes
  scope :visible, -> { where(hidden: false) }
  scope :verified, -> { where(verified_usage: true) }
  scope :with_review, -> { where.not(review: nil) }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_rating, ->(stars) { where(rating: stars) }

  # Callbacks
  after_save :update_agent_rating
  after_destroy :update_agent_rating

  # Methods
  def hide!(reason)
    update!(hidden: true, moderation_reason: reason)
  end

  def unhide!
    update!(hidden: false, moderation_reason: nil)
  end

  def rating_summary
    {
      id: id,
      rating: rating,
      review: hidden? ? nil : review,
      verified_usage: verified_usage,
      rating_dimensions: rating_dimensions,
      created_at: created_at,
      edited_at: edited_at
    }
  end

  private

  def one_rating_per_account
    existing = CommunityAgentRating.where(
      community_agent_id: community_agent_id,
      account_id: account_id
    ).where.not(id: id)

    if existing.exists?
      errors.add(:account, "has already rated this agent")
    end
  end

  def update_agent_rating
    community_agent.refresh_rating!
  end
end

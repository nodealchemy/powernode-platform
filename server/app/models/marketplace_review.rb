# frozen_string_literal: true

class MarketplaceReview < ApplicationRecord
  # Associations
  belongs_to :reviewable, polymorphic: true
  belongs_to :account
  belongs_to :user

  # Validations
  validates :rating, presence: true, inclusion: { in: 1..5 }
  validates :title, length: { maximum: 255 }
  validates :content, length: { maximum: 5000 }
  validates :moderation_status, inclusion: { in: %w[pending approved rejected flagged] }
  validates :reviewable_id, uniqueness: { scope: [ :account_id, :reviewable_type ],
                                          message: "already has a review from this account" }

  # Scopes
  scope :approved, -> { where(moderation_status: "approved") }
  scope :pending, -> { where(moderation_status: "pending") }
  scope :flagged, -> { where(moderation_status: "flagged") }
  scope :by_rating, ->(rating) { where(rating: rating) }
  scope :verified, -> { where(verified_purchase: true) }
  scope :recent, -> { order(created_at: :desc) }
  scope :most_helpful, -> { order(helpful_count: :desc) }

  # Class methods
  def self.average_rating_for(reviewable)
    where(reviewable: reviewable).approved.average(:rating)&.round(2) || 0.0
  end

  def self.rating_distribution_for(reviewable)
    where(reviewable: reviewable).approved.group(:rating).count
  end

  # Instance methods
  def approve!
    update!(moderation_status: "approved")
  end

  def reject!
    update!(moderation_status: "rejected")
  end

  def flag!
    update!(moderation_status: "flagged")
  end

  def increment_helpful!
    increment!(:helpful_count)
  end
end

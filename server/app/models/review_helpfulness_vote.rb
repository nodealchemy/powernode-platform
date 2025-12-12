# frozen_string_literal: true

class ReviewHelpfulnessVote < ApplicationRecord
  include AuditLogging

  # Associations
  belongs_to :app_review
  belongs_to :account

  # Validations
  validates :account_id, uniqueness: { scope: :app_review_id, message: "can only vote once per review" }
  validates :is_helpful, inclusion: { in: [ true, false ] }
  validates :voter_weight, numericality: { greater_than_or_equal_to: 0.0, less_than_or_equal_to: 5.0 }
  validates :ip_address, presence: true, length: { maximum: 45 }

  # Scopes
  scope :helpful, -> { where(is_helpful: true) }
  scope :unhelpful, -> { where(is_helpful: false) }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_weight, ->(min_weight = 1.0) { where("voter_weight >= ?", min_weight) }

  # Callbacks
  after_create :update_review_helpful_count
  after_update :update_review_helpful_count, if: :saved_change_to_is_helpful?
  after_destroy :update_review_helpful_count

  # Methods
  def helpful?
    is_helpful?
  end

  def unhelpful?
    !is_helpful?
  end

  def weighted_value
    is_helpful? ? voter_weight : -voter_weight
  end

  # Class methods for analytics
  def self.helpfulness_ratio
    total = count
    return 0.0 if total.zero?

    helpful.count.to_f / total
  end

  def self.average_weight
    average(:voter_weight)&.round(2) || 1.0
  end

  def self.weighted_helpfulness_score
    sum("CASE WHEN is_helpful THEN voter_weight ELSE -voter_weight END") || 0
  end

  private

  def update_review_helpful_count
    # Calculate weighted helpful count for the review
    weighted_score = app_review.review_helpfulness_votes
                              .sum("CASE WHEN is_helpful THEN voter_weight ELSE -voter_weight END")

    app_review.update_column(:helpful_count, [ weighted_score.round, 0 ].max)
  end
end

# frozen_string_literal: true

# Concern for models that can receive marketplace reviews
# Include in: Marketplace::Definition, Ai::WorkflowTemplate, IntegrationTemplate
module MarketplaceReviewable
  extend ActiveSupport::Concern

  included do
    has_many :marketplace_reviews, as: :reviewable, dependent: :destroy
  end

  # Returns the average rating from approved reviews
  def marketplace_rating
    marketplace_reviews.approved.average(:rating)&.round(2) || 0.0
  end

  # Returns the count of approved reviews
  def marketplace_review_count
    marketplace_reviews.approved.count
  end

  # Returns rating distribution { 1 => count, 2 => count, ... }
  def rating_distribution
    MarketplaceReview.rating_distribution_for(self)
  end

  # Check if a user/account has already reviewed this item
  def reviewed_by?(account)
    marketplace_reviews.exists?(account: account)
  end

  # Get the review by a specific account
  def review_by(account)
    marketplace_reviews.find_by(account: account)
  end
end

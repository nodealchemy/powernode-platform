# frozen_string_literal: true

class ReviewAggregationCache < ApplicationRecord
  self.table_name = 'review_aggregation_cache'
  include AuditLogging
  
  # Associations
  belongs_to :app
  
  # Validations
  validates :app_id, uniqueness: true
  validates :average_rating, numericality: { greater_than_or_equal_to: 0.0, less_than_or_equal_to: 5.0 }
  validates :total_reviews, numericality: { greater_than_or_equal_to: 0 }
  validates :positive_sentiment_percentage, :neutral_sentiment_percentage, :negative_sentiment_percentage,
            numericality: { greater_than_or_equal_to: 0.0, less_than_or_equal_to: 100.0 }
  
  # Scopes
  scope :high_rated, -> { where('average_rating >= 4.0') }
  scope :low_rated, -> { where('average_rating <= 2.0') }
  scope :well_reviewed, ->(min_reviews = 10) { where('total_reviews >= ?', min_reviews) }
  scope :recently_updated, -> { where('last_updated >= ?', 1.hour.ago) }
  scope :stale, -> { where('last_updated < ?', 1.day.ago) }
  
  # Methods for cache management
  def self.refresh_for_app(app)
    cache_record = find_or_initialize_by(app: app)
    cache_record.refresh_from_reviews!
    cache_record
  end
  
  def refresh_from_reviews!
    reviews = app.app_reviews.where(removed: false)
    
    # Basic aggregations
    self.total_reviews = reviews.count
    self.average_rating = reviews.average(:rating)&.round(2) || 0.0
    
    # Rating distribution
    rating_counts = reviews.group(:rating).count
    self.one_star_count = rating_counts[1] || 0
    self.two_star_count = rating_counts[2] || 0
    self.three_star_count = rating_counts[3] || 0
    self.four_star_count = rating_counts[4] || 0
    self.five_star_count = rating_counts[5] || 0
    
    # Sentiment analysis
    sentiment_counts = reviews.where.not(sentiment: nil).group(:sentiment).count
    total_with_sentiment = sentiment_counts.values.sum
    
    if total_with_sentiment > 0
      self.positive_sentiment_percentage = ((sentiment_counts['positive'] || 0).to_f / total_with_sentiment * 100).round(2)
      self.neutral_sentiment_percentage = ((sentiment_counts['neutral'] || 0).to_f / total_with_sentiment * 100).round(2)
      self.negative_sentiment_percentage = ((sentiment_counts['negative'] || 0).to_f / total_with_sentiment * 100).round(2)
    else
      self.positive_sentiment_percentage = 0.0
      self.neutral_sentiment_percentage = 0.0
      self.negative_sentiment_percentage = 0.0
    end
    
    # Additional metrics
    self.verified_reviews_count = reviews.where(verified_purchase: true).count
    self.reviews_with_content_count = reviews.where.not(content: [nil, '']).count
    self.average_helpfulness = reviews.average(:helpful_count)&.round(2) || 0.0
    
    # Monthly velocity
    current_month = Time.current.beginning_of_month
    self.monthly_review_velocity = reviews.where(created_at: current_month..Time.current).count
    
    # Additional metrics in JSON
    self.additional_metrics = {
      reviews_with_media: app.app_reviews.joins(:review_media_attachments).distinct.count,
      average_content_length: reviews.where.not(content: [nil, '']).average('LENGTH(content)')&.round(0) || 0,
      response_rate: calculate_response_rate,
      flagged_reviews_count: reviews.where(flagged_for_review: true).count,
      quality_distribution: calculate_quality_distribution,
      recent_trends: calculate_recent_trends
    }
    
    self.last_updated = Time.current
    save!
  end
  
  def stale?
    last_updated < 1.hour.ago
  end
  
  def refresh_if_stale!
    refresh_from_reviews! if stale?
  end
  
  # Display methods
  def rating_distribution
    {
      1 => one_star_count,
      2 => two_star_count,
      3 => three_star_count,
      4 => four_star_count,
      5 => five_star_count
    }
  end
  
  def sentiment_distribution
    {
      positive: positive_sentiment_percentage,
      neutral: neutral_sentiment_percentage,
      negative: negative_sentiment_percentage
    }
  end
  
  def verification_rate
    return 0.0 if total_reviews.zero?
    
    (verified_reviews_count.to_f / total_reviews * 100).round(1)
  end
  
  def content_rate
    return 0.0 if total_reviews.zero?
    
    (reviews_with_content_count.to_f / total_reviews * 100).round(1)
  end
  
  def overall_sentiment
    return 'neutral' if positive_sentiment_percentage == neutral_sentiment_percentage && 
                       neutral_sentiment_percentage == negative_sentiment_percentage
    
    max_sentiment = [
      ['positive', positive_sentiment_percentage],
      ['neutral', neutral_sentiment_percentage],
      ['negative', negative_sentiment_percentage]
    ].max_by { |_, percentage| percentage }
    
    max_sentiment.first
  end
  
  private
  
  def calculate_response_rate
    reviews_with_responses = app.app_reviews
                               .joins(:review_responses)
                               .where(review_responses: { status: 'approved' })
                               .distinct
                               .count
    
    return 0.0 if total_reviews.zero?
    
    (reviews_with_responses.to_f / total_reviews * 100).round(1)
  end
  
  def calculate_quality_distribution
    quality_ranges = [
      [0.0, 1.0],   # Very Low
      [1.0, 2.0],   # Low  
      [2.0, 3.0],   # Fair
      [3.0, 4.0],   # Good
      [4.0, 5.0]    # Excellent
    ]
    
    distribution = {}
    quality_ranges.each_with_index do |(min, max), index|
      count = app.app_reviews.where(quality_score: min..max).count
      distribution["quality_#{index + 1}"] = count
    end
    
    distribution
  end
  
  def calculate_recent_trends
    current_month = Date.current.beginning_of_month
    last_month = current_month - 1.month
    
    current_count = app.app_reviews.where(created_at: current_month..Time.current).count
    last_count = app.app_reviews.where(created_at: last_month...current_month).count
    
    growth = last_count.zero? ? 0.0 : ((current_count - last_count).to_f / last_count * 100).round(1)
    
    {
      current_month_reviews: current_count,
      last_month_reviews: last_count,
      month_over_month_growth: growth
    }
  end
end
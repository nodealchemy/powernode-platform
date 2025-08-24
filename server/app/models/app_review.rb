# frozen_string_literal: true

class AppReview < ApplicationRecord
  include AuditLogging
  
  # Associations
  belongs_to :app
  belongs_to :account
  
  # Validations
  validates :rating, presence: true, inclusion: { in: 1..5 }
  validates :title, length: { maximum: 255 }
  validates :content, length: { maximum: 2000 }
  validates :account_id, uniqueness: { scope: :app_id }
  validates :helpful_count, numericality: { greater_than_or_equal_to: 0 }
  
  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :by_rating, ->(rating) { where(rating: rating) }
  scope :positive, -> { where('rating >= 4') }
  scope :negative, -> { where('rating <= 2') }
  scope :neutral, -> { where(rating: 3) }
  scope :helpful, -> { where('helpful_count > 0').order(helpful_count: :desc) }
  scope :with_content, -> { where.not(content: [nil, '']) }
  
  # Callbacks
  after_create :log_review_created
  after_update :log_review_updated, if: :saved_changes?
  after_create :update_app_rating_cache
  after_update :update_app_rating_cache, if: :saved_change_to_rating?
  after_destroy :update_app_rating_cache
  
  # Rating methods
  def positive?
    rating >= 4
  end
  
  def negative?
    rating <= 2
  end
  
  def neutral?
    rating == 3
  end
  
  def star_display
    '★' * rating + '☆' * (5 - rating)
  end
  
  # Helpfulness methods
  def helpful?
    helpful_count > 0
  end
  
  def mark_helpful!
    increment!(:helpful_count)
    log_marked_helpful
  end
  
  def mark_unhelpful!
    decrement!(:helpful_count) if helpful_count > 0
    log_marked_unhelpful
  end
  
  # Content methods
  def has_content?
    content.present?
  end
  
  def has_title?
    title.present?
  end
  
  def content_summary(length = 100)
    return '' unless content.present?
    
    content.length <= length ? content : "#{content[0...length]}..."
  end
  
  def word_count
    return 0 unless content.present?
    
    content.split.length
  end
  
  # Display methods
  def display_title
    title.present? ? title : "#{rating}-star review"
  end
  
  def reviewer_name
    account.name || "User #{account.id[0..7]}"
  end
  
  def formatted_date
    created_at.strftime('%B %d, %Y')
  end
  
  def time_ago
    time_diff = Time.current - created_at
    
    case time_diff
    when 0..59
      'just now'
    when 60..3599
      "#{(time_diff / 60).round} minutes ago"
    when 3600..86399
      "#{(time_diff / 3600).round} hours ago"
    when 86400..2591999
      "#{(time_diff / 86400).round} days ago"
    else
      formatted_date
    end
  end
  
  # Verification methods
  def verified_purchase?
    AppSubscription.exists?(account: account, app: app)
  end
  
  def long_term_user?
    subscription = AppSubscription.find_by(account: account, app: app)
    return false unless subscription
    
    subscription.subscription_age_in_days > 30
  end
  
  # Moderation methods
  def flag_for_review!(reason = nil)
    update!(flagged_for_review: true, flag_reason: reason)
    log_flagged_for_review(reason)
  end
  
  def approve_after_review!
    update!(flagged_for_review: false, flag_reason: nil, reviewed_at: Time.current)
    log_approved_after_review
  end
  
  def remove_after_review!(reason = nil)
    update!(removed: true, removal_reason: reason, reviewed_at: Time.current)
    log_removed_after_review(reason)
  end
  
  # Analytics methods
  def self.average_rating
    average(:rating)&.round(1) || 0.0
  end
  
  def self.rating_distribution
    group(:rating).count.sort.to_h
  end
  
  def self.sentiment_analysis
    total = count
    return {} if total.zero?
    
    {
      positive: positive.count.to_f / total * 100,
      neutral: neutral.count.to_f / total * 100,
      negative: negative.count.to_f / total * 100
    }.transform_values { |v| v.round(1) }
  end
  
  def self.monthly_review_count
    where(created_at: 1.month.ago..Time.current).count
  end
  
  def self.review_velocity
    recent_count = where(created_at: 1.week.ago..Time.current).count
    previous_count = where(created_at: 2.weeks.ago..1.week.ago).count
    
    return 0 if previous_count.zero?
    
    ((recent_count - previous_count).to_f / previous_count * 100).round(1)
  end
  
  # Search and filtering
  def self.search_content(query)
    return all if query.blank?
    
    where("title ILIKE :query OR content ILIKE :query", query: "%#{query}%")
  end
  
  def self.by_date_range(start_date, end_date)
    where(created_at: start_date..end_date)
  end
  
  def self.by_helpfulness(min_helpful = 1)
    where('helpful_count >= ?', min_helpful)
  end
  
  # Comparison methods
  def similar_reviews(limit = 5)
    self.class.where(app: app)
             .where.not(id: id)
             .where(rating: rating)
             .order(helpful_count: :desc)
             .limit(limit)
  end
  
  def reviewer_other_reviews(limit = 3)
    AppReview.where(account: account)
             .where.not(id: id)
             .includes(:app)
             .order(created_at: :desc)
             .limit(limit)
  end
  
  private
  
  def update_app_rating_cache
    # This would typically update a cached average rating on the app
    # For now, we'll just trigger a recalculation
    app.touch # This will trigger any app caching mechanisms
  end
  
  def log_review_created
    Rails.logger.info "App review created: #{rating} stars for #{app.name} by account #{account_id}"
  end
  
  def log_review_updated
    Rails.logger.info "App review updated: #{id} - Changes: #{saved_changes.keys.join(', ')}"
  end
  
  def log_marked_helpful
    Rails.logger.info "App review marked helpful: #{id} (now #{helpful_count} helpful votes)"
  end
  
  def log_marked_unhelpful
    Rails.logger.info "App review marked unhelpful: #{id} (now #{helpful_count} helpful votes)"
  end
  
  def log_flagged_for_review(reason)
    Rails.logger.info "App review flagged: #{id} - Reason: #{reason}"
  end
  
  def log_approved_after_review
    Rails.logger.info "App review approved after moderation: #{id}"
  end
  
  def log_removed_after_review(reason)
    Rails.logger.info "App review removed after moderation: #{id} - Reason: #{reason}"
  end
end
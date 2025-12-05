# frozen_string_literal: true

class MarketplaceListing < ApplicationRecord
  include Auditable

  # Associations
  belongs_to :app
  
  # Validations
  validates :title, presence: true, length: { minimum: 2, maximum: 255 }
  validates :short_description, length: { maximum: 500 }
  validates :long_description, length: { maximum: 10000 }
  validates :category, length: { maximum: 100 }
  validates :review_status, presence: true, inclusion: { in: %w[pending approved rejected] }
  validates :documentation_url, :support_url, :homepage_url, 
            format: { with: URI::DEFAULT_PARSER.make_regexp, allow_blank: true }
  
  # JSON validations  
  validates :tags, presence: true
  # Note: screenshots can be empty initially
  
  # Scopes
  scope :pending_review, -> { where(review_status: 'pending') }
  scope :approved, -> { where(review_status: 'approved') }
  scope :rejected, -> { where(review_status: 'rejected') }
  scope :published, -> { approved.where.not(published_at: nil) }
  scope :featured, -> { where(featured: true) }
  scope :by_category, ->(category) { where(category: category) }
  scope :recent, -> { order(published_at: :desc, created_at: :desc) }
  scope :popular, -> { 
    if ActiveRecord::Base.connection.table_exists?('app_subscriptions')
      joins(app: :app_subscriptions).group('marketplace_listings.id').order('COUNT(app_subscriptions.id) DESC')
    else
      order(created_at: :desc)
    end
  }
  scope :with_tags, ->(tags) { where('tags @> ?', tags.to_json) }
  
  # Callbacks
  before_save :normalize_urls
  before_save :normalize_tags
  after_update :log_status_changes, if: :saved_change_to_review_status?
  after_update :log_featured_changes, if: :saved_change_to_featured?
  
  # Status methods
  def pending?
    review_status == 'pending'
  end
  
  def approved?
    review_status == 'approved'
  end
  
  def rejected?
    review_status == 'rejected'
  end
  
  def published?
    approved? && published_at.present?
  end
  
  def featured?
    featured == true
  end
  
  # Review methods
  def approve!(reviewer = nil, notes = nil)
    return false unless pending?
    
    transaction do
      update!(
        review_status: 'approved',
        review_notes: notes,
        published_at: Time.current
      )
      app.publish! if app.under_review?
      log_approval(reviewer)
    end
    true
  rescue ActiveRecord::RecordInvalid
    false
  end
  
  def reject!(reviewer = nil, notes = nil)
    return false unless pending?
    
    transaction do
      update!(
        review_status: 'rejected',
        review_notes: notes,
        published_at: nil
      )
      app.reject!(notes) if app.under_review?
      log_rejection(reviewer, notes)
    end
    true
  rescue ActiveRecord::RecordInvalid
    false
  end
  
  def resubmit!
    return false unless rejected?
    
    update!(
      review_status: 'pending',
      review_notes: nil,
      published_at: nil
    )
    log_resubmission
  end
  
  # Featured methods
  def feature!
    update!(featured: true)
    log_featured
  end
  
  def unfeature!
    update!(featured: false)
    log_unfeatured
  end
  
  # Tag methods
  def add_tag(tag)
    normalized_tag = tag.to_s.downcase.strip
    return false if normalized_tag.empty?
    
    self.tags = (tags + [normalized_tag]).uniq
    save
  end
  
  def remove_tag(tag)
    self.tags = tags - [tag.to_s.downcase.strip]
    save
  end
  
  def has_tag?(tag)
    tags.include?(tag.to_s.downcase.strip)
  end
  
  # Screenshot methods
  def add_screenshot(url, caption = nil)
    screenshot = {
      'url' => url,
      'caption' => caption,
      'order' => screenshots.length
    }
    
    self.screenshots = screenshots + [screenshot]
    save
  end
  
  def remove_screenshot(index)
    return false if index >= screenshots.length
    
    self.screenshots = screenshots.reject.with_index { |_, i| i == index }
    # Reorder remaining screenshots
    self.screenshots = screenshots.map.with_index do |screenshot, i|
      screenshot.merge('order' => i)
    end
    save
  end
  
  def reorder_screenshots(new_order)
    return false if new_order.length != screenshots.length
    
    reordered = new_order.map.with_index do |original_index, new_index|
      screenshots[original_index].merge('order' => new_index)
    end
    
    self.screenshots = reordered
    save
  end
  
  # Search methods
  def self.search(query)
    return all if query.blank?
    
    where(
      "title ILIKE :query OR short_description ILIKE :query OR long_description ILIKE :query OR tags @> :tag_query",
      query: "%#{query}%",
      tag_query: [query.downcase].to_json
    )
  end
  
  def self.filter_by_category(category)
    return all if category.blank?
    
    where(category: category)
  end
  
  def self.filter_by_tags(tag_list)
    return all if tag_list.blank?
    
    tags_array = Array(tag_list).map(&:downcase)
    where('tags @> ?', tags_array.to_json)
  end
  
  # Analytics methods
  def view_count
    return 0 unless ActiveRecord::Base.connection.table_exists?('app_analytics')
    app.app_analytics.where(metric_name: 'listing_view').sum(:metric_value)
  rescue
    0
  end
  
  def subscription_count
    return 0 unless ActiveRecord::Base.connection.table_exists?('app_subscriptions')
    app.subscription_count
  rescue
    0
  end
  
  def conversion_rate
    views = view_count
    return 0.0 if views.zero?
    
    (subscription_count.to_f / views * 100).round(2)
  end
  
  def average_rating
    return 0.0 unless app.respond_to?(:average_rating)
    app.average_rating
  rescue
    0.0
  end
  
  def review_count
    return 0 unless app.respond_to?(:total_reviews)
    app.total_reviews
  rescue
    0
  end
  
  # URL helpers
  def has_documentation?
    documentation_url.present?
  end
  
  def has_support?
    support_url.present?
  end
  
  def has_homepage?
    homepage_url.present?
  end
  
  # Content helpers
  def primary_screenshot
    screenshots.first
  end
  
  def screenshot_urls
    screenshots.compact
  end
  
  def formatted_tags
    tags.map(&:titleize)
  end
  
  def tag_list
    tags.join(', ')
  end
  
  # Comparison methods
  def similar_listings(limit = 5)
    self.class.approved
        .published
        .where.not(id: id)
        .where(category: category)
        .limit(limit)
        .order(:created_at)
  end
  
  def competing_listings(limit = 5)
    # Find listings with similar tags
    self.class.approved
        .published
        .where.not(id: id)
        .where('tags && ?', tags.to_json)
        .limit(limit)
        .order('created_at DESC')
  end
  
  private
  
  def normalize_urls
    %w[documentation_url support_url homepage_url].each do |url_field|
      url = send(url_field)
      next if url.blank?
      
      # Add protocol if missing
      unless url.match?(/\Ahttps?:\/\//)
        send("#{url_field}=", "https://#{url}")
      end
    end
  end
  
  def normalize_tags
    return if tags.blank?
    
    self.tags = tags.map do |tag|
      tag.to_s.downcase.strip.gsub(/[^a-z0-9\-_]/, '')
    end.reject(&:blank?).uniq.first(10) # Limit to 10 tags
  end
  
  def log_status_changes
    Rails.logger.info "Marketplace listing #{id} status changed to #{review_status}"
  end
  
  def log_featured_changes
    action = featured? ? 'featured' : 'unfeatured'
    Rails.logger.info "Marketplace listing #{id} #{action}"
  end
  
  def log_approval(reviewer)
    Rails.logger.info "Marketplace listing approved: #{title} (#{id}) by #{reviewer || 'system'}"
  end
  
  def log_rejection(reviewer, notes)
    Rails.logger.info "Marketplace listing rejected: #{title} (#{id}) by #{reviewer || 'system'} - #{notes}"
  end
  
  def log_resubmission
    Rails.logger.info "Marketplace listing resubmitted: #{title} (#{id})"
  end
  
  def log_featured
    Rails.logger.info "Marketplace listing featured: #{title} (#{id})"
  end
  
  def log_unfeatured
    Rails.logger.info "Marketplace listing unfeatured: #{title} (#{id})"
  end
end
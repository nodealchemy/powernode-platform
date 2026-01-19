# frozen_string_literal: true

class MarketplaceCategory < ApplicationRecord
  include AuditLogging

  # Associations
  has_many :apps, foreign_key: :category, primary_key: :slug
  has_many :marketplace_listings, foreign_key: :category, primary_key: :slug

  # Validations
  validates :name, presence: true, length: { minimum: 2, maximum: 255 }
  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9\-_]+\z/ }
  validates :description, length: { maximum: 1000 }
  validates :icon, length: { maximum: 100 }
  validates :sort_order, numericality: { greater_than_or_equal_to: 0 }

  # Scopes
  scope :active, -> { where(is_active: true) }
  scope :inactive, -> { where(is_active: false) }
  scope :ordered, -> { order(:sort_order, :name) }
  scope :with_apps, -> { joins(:apps).distinct }
  scope :with_published_apps, -> { joins(:apps).where(apps: { status: "published" }).distinct }

  # Callbacks
  before_validation :generate_slug, if: :name_changed?
  after_create :log_category_created
  after_update :log_category_updated, if: :saved_changes?

  # Status methods
  def active?
    is_active == true
  end

  def inactive?
    is_active == false
  end

  # App counting methods
  def total_apps_count
    apps.count
  end

  def published_apps_count
    apps.published.count
  end

  def draft_apps_count
    apps.draft.count
  end

  def under_review_apps_count
    apps.under_review.count
  end

  # Listing methods
  def total_listings_count
    marketplace_listings.count
  end

  def approved_listings_count
    marketplace_listings.approved.count
  end

  def published_listings_count
    marketplace_listings.published.count
  end

  def featured_listings_count
    marketplace_listings.featured.count
  end

  # Popular apps in category
  def popular_apps(limit = 10)
    apps.published
        .joins(:app_subscriptions)
        .group("apps.id")
        .order("COUNT(app_subscriptions.id) DESC")
        .limit(limit)
  end

  def recent_apps(limit = 10)
    apps.published.order(published_at: :desc).limit(limit)
  end

  def featured_apps(limit = 5)
    marketplace_listings.featured
                       .published
                       .joins(:app)
                       .includes(:app)
                       .limit(limit)
                       .map(&:app)
  end

  # Category statistics
  def average_app_rating
    app_ids = apps.published.pluck(:id)
    return 0.0 if app_ids.empty?

    Marketplace::Review.where(app_id: app_ids).average(:rating)&.round(1) || 0.0
  end

  def total_subscribers
    Marketplace::Subscription.joins(:app)
                   .where(apps: { category: slug, status: "published" })
                   .where(status: "active")
                   .count
  end

  def total_category_revenue
    Marketplace::Subscription.joins(:app, :app_plan)
                   .where(apps: { category: slug, status: "published" })
                   .where(status: "active")
                   .sum("app_plans.price_cents") / 100.0
  end

  # Category management
  def activate!
    update!(is_active: true)
    log_category_activated
  end

  def deactivate!
    update!(is_active: false)
    log_category_deactivated
  end

  def reorder!(new_sort_order)
    update!(sort_order: new_sort_order)
    log_category_reordered(new_sort_order)
  end

  # Icon methods
  def has_icon?
    icon.present?
  end

  def icon_class
    icon.present? ? icon : "default-category-icon"
  end

  def formatted_icon
    return icon if icon.blank?

    # Handle different icon formats
    case icon
    when /\A[a-z-]+\z/ # CSS class format
      icon
    when /\A\p{Emoji}\z/ # Emoji format
      icon
    when /\Afa[sr]? fa-/ # FontAwesome format
      icon
    else
      "category-#{slug}"
    end
  end

  # Search and filtering
  def self.search(query)
    return ordered if query.blank?

    where("name ILIKE :query OR description ILIKE :query", query: "%#{query}%")
      .ordered
  end

  def self.with_minimum_apps(count = 1)
    joins(:apps)
      .where(apps: { status: "published" })
      .group("marketplace_categories.id")
      .having("COUNT(apps.id) >= ?", count)
  end

  # Analytics methods
  def growth_metrics(days = 30)
    current_period = apps.where(created_at: days.days.ago..Time.current).count
    previous_period = apps.where(created_at: (days * 2).days.ago..days.days.ago).count

    {
      current_apps: current_period,
      previous_apps: previous_period,
      growth_rate: previous_period > 0 ? ((current_period - previous_period).to_f / previous_period * 100).round(1) : 0.0,
      total_apps: total_apps_count
    }
  end

  def subscription_metrics
    {
      total_subscriptions: total_subscribers,
      average_rating: average_app_rating,
      total_revenue: total_category_revenue,
      published_apps: published_apps_count,
      featured_apps: featured_listings_count
    }
  end

  # Comparison methods
  def similar_categories(limit = 5)
    # Find categories with similar app counts or names
    self.class.active
        .where.not(id: id)
        .order("ABS(sort_order - #{sort_order})")
        .limit(limit)
  end

  def competing_categories
    # Categories with similar app types or overlapping keywords
    keywords = name.downcase.split(/\W+/)

    self.class.active
        .where.not(id: id)
        .where(
          keywords.map { |keyword| "name ILIKE '%#{keyword}%' OR description ILIKE '%#{keyword}%'" }.join(" OR ")
        )
        .limit(3)
  end

  # Display methods
  def display_name
    name.titleize
  end

  def app_count_text
    count = published_apps_count
    case count
    when 0
      "No apps"
    when 1
      "1 app"
    else
      "#{count} apps"
    end
  end

  def activity_level
    count = published_apps_count
    case count
    when 0..2
      "Low"
    when 3..10
      "Medium"
    when 11..25
      "High"
    else
      "Very High"
    end
  end

  private

  def generate_slug
    return if slug.present? && !name_changed?

    base_slug = name.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/-{2,}/, "-").strip("-")
    candidate_slug = base_slug
    counter = 1

    while MarketplaceCategory.exists?(slug: candidate_slug)
      candidate_slug = "#{base_slug}-#{counter}"
      counter += 1
    end

    self.slug = candidate_slug
  end

  def log_category_created
    Rails.logger.info "Marketplace category created: #{name} (#{slug})"
  end

  def log_category_updated
    Rails.logger.info "Marketplace category updated: #{name} (#{slug}) - Changes: #{saved_changes.keys.join(', ')}"
  end

  def log_category_activated
    Rails.logger.info "Marketplace category activated: #{name} (#{slug})"
  end

  def log_category_deactivated
    Rails.logger.info "Marketplace category deactivated: #{name} (#{slug})"
  end

  def log_category_reordered(new_order)
    Rails.logger.info "Marketplace category reordered: #{name} (#{slug}) to position #{new_order}"
  end
end

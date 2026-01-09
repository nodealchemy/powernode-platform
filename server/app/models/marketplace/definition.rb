# frozen_string_literal: true

module Marketplace
  class Definition < ApplicationRecord
    # Explicit table name since "apps" doesn't follow "app_definitions" pattern
    self.table_name = "apps"

    # Associations
    belongs_to :account
    has_many :plans, class_name: "Marketplace::Plan", foreign_key: "app_id", dependent: :destroy
    has_many :features, class_name: "Marketplace::Feature", foreign_key: "app_id", dependent: :destroy
    has_one :marketplace_listing, foreign_key: "app_id", dependent: :destroy
    has_many :subscriptions, class_name: "Marketplace::Subscription", foreign_key: "app_id", dependent: :destroy
    has_many :reviews, class_name: "Marketplace::Review", foreign_key: "app_id", dependent: :destroy
    has_one :aggregation_cache, class_name: "Review::AggregationCache", foreign_key: "app_id", dependent: :destroy
    has_many :app_analytics, foreign_key: "app_id", dependent: :destroy
    has_many :endpoints, class_name: "Marketplace::Endpoint", foreign_key: "app_id", dependent: :destroy
    has_many :webhooks, class_name: "Marketplace::Webhook", foreign_key: "app_id", dependent: :destroy
    has_many :subscribers, through: :subscriptions, source: :account

    # Validations
    validates :name, presence: true, length: { minimum: 2, maximum: 255 }
    validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9\-_]+\z/ }
    validates :version, presence: true, format: { with: /\A\d+\.\d+\.\d+\z/ }
    validates :status, presence: true, inclusion: { in: %w[draft review published inactive] }
    validates :category, length: { maximum: 100 }
    validates :description, length: { maximum: 1000 }
    validates :short_description, length: { maximum: 500 }
    validates :long_description, length: { maximum: 10000 }

    # Scopes
    scope :draft, -> { where(status: "draft") }
    scope :under_review, -> { where(status: "review") }
    scope :published, -> { where(status: "published") }
    scope :inactive, -> { where(status: "inactive") }
    scope :by_category, ->(category) { where(category: category) }
    scope :recent, -> { order(created_at: :desc) }
    scope :popular, -> { joins(:subscriptions).group("apps.id").order("COUNT(app_subscriptions.id) DESC") }

    # Callbacks
    before_validation :generate_slug, if: :name_changed?
    before_save :normalize_category
    after_create :log_app_creation
    after_update :log_app_updates
    after_update :sync_marketplace_listing, if: :saved_change_to_status?

    # Status methods
    def draft?
      status == "draft"
    end

    def under_review?
      status == "review"
    end

    def published?
      status == "published"
    end

    def inactive?
      status == "inactive"
    end

    # Publishing methods
    def can_publish?
      draft? && plans.active.any? && features.any?
    end

    def submit_for_review!
      return false unless can_publish?

      transaction do
        update!(status: "review")
        create_or_update_marketplace_listing
        log_app_submission
      end
      true
    rescue ActiveRecord::RecordInvalid
      false
    end

    def publish!
      return false unless under_review?

      transaction do
        update!(status: "published", published_at: Time.current)
        marketplace_listing&.update!(review_status: "approved", published_at: Time.current)
        log_app_publication
      end
      true
    rescue ActiveRecord::RecordInvalid
      false
    end

    def reject!(reason = nil)
      return false unless under_review?

      transaction do
        update!(status: "draft")
        marketplace_listing&.update!(review_status: "rejected", review_notes: reason)
        log_app_rejection(reason)
      end
      true
    rescue ActiveRecord::RecordInvalid
      false
    end

    # Feature methods
    def enabled_features_for_plan(plan)
      return [] unless plan.is_a?(Marketplace::Plan) && plan.app == self

      features.where(slug: plan.features).includes(:dependencies)
    end

    def feature_enabled?(feature_slug, plan = nil)
      return false unless features.exists?(slug: feature_slug)

      if plan
        plan.features.include?(feature_slug.to_s)
      else
        features.find_by(slug: feature_slug)&.default_enabled || false
      end
    end

    # Analytics methods
    def record_metric(metric_name, value, metadata = {})
      app_analytics.create!(
        metric_name: metric_name,
        metric_value: value,
        metadata: metadata,
        recorded_at: Time.current
      )
    end

    def subscription_count
      subscriptions.active.count
    end

    def average_rating
      reviews.average(:rating)&.round(1) || 0.0
    end

    def total_reviews
      reviews.count
    end

    # Revenue methods
    def monthly_revenue
      subscriptions.active
                   .joins(:plan)
                   .where(app_plans: { billing_interval: "monthly" })
                   .sum("app_plans.price_cents") / 100.0
    end

    def yearly_revenue
      subscriptions.active
                   .joins(:plan)
                   .where(app_plans: { billing_interval: "yearly" })
                   .sum("app_plans.price_cents") / 100.0
    end

    def total_revenue
      monthly_revenue * 12 + yearly_revenue
    end

    # Versioning methods
    def increment_version!(version_type = :patch)
      current_version = version.split(".").map(&:to_i)

      case version_type
      when :major
        current_version[0] += 1
        current_version[1] = 0
        current_version[2] = 0
      when :minor
        current_version[1] += 1
        current_version[2] = 0
      when :patch
        current_version[2] += 1
      end

      update!(version: current_version.join("."))
    end

    private

    def generate_slug
      return if slug.present? && !name_changed?

      base_slug = name.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/-{2,}/, "-").gsub(/^-+|-+$/, "")
      candidate_slug = base_slug
      counter = 1

      while Marketplace::Definition.exists?(slug: candidate_slug)
        candidate_slug = "#{base_slug}-#{counter}"
        counter += 1
      end

      self.slug = candidate_slug
    end

    def normalize_category
      self.category = category&.downcase&.strip
    end

    def create_or_update_marketplace_listing
      if marketplace_listing
        marketplace_listing.update!(
          title: name,
          short_description: description&.truncate(500),
          long_description: long_description,
          category: category,
          review_status: "pending"
        )
      else
        create_marketplace_listing!(
          title: name,
          short_description: description&.truncate(500),
          long_description: long_description,
          category: category,
          review_status: "pending"
        )
      end
    end

    def sync_marketplace_listing
      return unless marketplace_listing

      if published?
        marketplace_listing.update(published_at: published_at)
      elsif inactive?
        marketplace_listing.update(published_at: nil)
      end
    end

    def log_app_creation
      Rails.logger.info "App created: #{name} (#{id}) by Account #{account_id}"
    end

    def log_app_updates
      return unless saved_changes.any?

      Rails.logger.info "App updated: #{name} (#{id}) - Changes: #{saved_changes.keys.join(', ')}"
    end

    def log_app_submission
      Rails.logger.info "App submitted for review: #{name} (#{id})"
    end

    def log_app_publication
      Rails.logger.info "App published: #{name} (#{id})"
      record_metric("publication", 1, { published_at: published_at })
    end

    def log_app_rejection(reason)
      Rails.logger.info "App rejected: #{name} (#{id}) - Reason: #{reason}"
      record_metric("rejection", 1, { reason: reason })
    end
  end
end

# Backward compatibility alias
App = Marketplace::Definition unless defined?(App)

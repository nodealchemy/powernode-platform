# frozen_string_literal: true

module Ai
  class AgentTemplate < ApplicationRecord
    self.table_name = "ai_agent_templates"

    # Associations
    belongs_to :source_agent, class_name: "Ai::Agent", optional: true

    has_many :installations, class_name: "Ai::AgentInstallation", foreign_key: :agent_template_id, dependent: :destroy
    has_many :reviews, class_name: "Ai::AgentReview", foreign_key: :agent_template_id, dependent: :destroy

    # Enterprise associations - marketplace monetization & publishing
    if defined?(PowernodeEnterprise::Engine)
      belongs_to :publisher, class_name: "Ai::PublisherAccount", foreign_key: "ai_publisher_account_id", optional: true
      has_many :marketplace_transactions, class_name: "Ai::MarketplaceTransaction", foreign_key: "ai_agent_template_id"
    end

    # Validations
    validates :name, presence: true
    validates :slug, presence: true, uniqueness: true,
              format: { with: /\A[a-z0-9-]+\z/, message: "only allows lowercase letters, numbers, and hyphens" }
    validates :version, presence: true
    validates :status, presence: true, inclusion: { in: %w[draft pending_review published rejected archived suspended] }
    validates :visibility, presence: true, inclusion: { in: %w[private unlisted public enterprise] }
    validates :pricing_type, presence: true, inclusion: { in: %w[free one_time subscription usage_based freemium] }
    validates :price_usd, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
    validates :monthly_price_usd, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

    # Scopes
    scope :published, -> { where(status: "published") }
    scope :public_templates, -> { where(visibility: "public") }
    scope :featured, -> { where(is_featured: true) }
    scope :verified, -> { where(is_verified: true) }
    scope :free, -> { where(pricing_type: "free") }
    scope :paid, -> { where.not(pricing_type: "free") }
    scope :by_category, ->(category) { where(category: category) }
    scope :by_vertical, ->(vertical) { where(vertical: vertical) }
    scope :popular, -> { order(installation_count: :desc) }
    scope :top_rated, -> { order(average_rating: :desc) }

    # Callbacks
    before_validation :generate_slug, on: :create, if: -> { slug.blank? && name.present? }

    # Methods
    def published?
      status == "published"
    end

    def free?
      pricing_type == "free"
    end

    def requires_payment?
      !free? && (price_usd.to_f > 0 || monthly_price_usd.to_f > 0)
    end

    def publish!
      return false unless can_publish?

      update!(status: "published", published_at: Time.current)
    end

    def can_publish?
      %w[draft pending_review rejected].include?(status)
    end

    def update_rating!
      new_average = reviews.published.average(:rating)&.round(2)
      new_count = reviews.published.count
      update!(average_rating: new_average, review_count: new_count)
    end

    def increment_installations!
      increment!(:installation_count)
      increment!(:active_installations)
    end

    def decrement_active_installations!
      decrement!(:active_installations) if active_installations > 0
    end

    private

    def generate_slug
      base_slug = name.parameterize
      self.slug = "#{publisher.publisher_slug}-#{base_slug}"
    end
  end
end

# frozen_string_literal: true

module Ai
  class AgentReview < ApplicationRecord
    self.table_name = "ai_agent_reviews"

    # Associations
    belongs_to :agent_template, class_name: "Ai::AgentTemplate"
    belongs_to :account
    belongs_to :user
    belongs_to :installation, class_name: "Ai::AgentInstallation", optional: true

    # Validations
    validates :rating, presence: true, inclusion: { in: 1..5 }
    validates :status, presence: true, inclusion: { in: %w[pending published hidden flagged removed] }
    validates :account_id, uniqueness: { scope: :agent_template_id, message: "has already reviewed this template" }

    # Scopes
    scope :published, -> { where(status: "published") }
    scope :pending, -> { where(status: "pending") }
    scope :verified, -> { where(is_verified_purchase: true) }
    scope :by_rating, ->(rating) { where(rating: rating) }
    scope :recent, -> { order(created_at: :desc) }
    scope :helpful, -> { order(helpful_count: :desc) }

    # Callbacks
    after_save :update_template_rating, if: :saved_change_to_rating?
    after_save :update_template_rating, if: :saved_change_to_status?

    # Methods
    def published?
      status == "published"
    end

    def verified_purchase?
      is_verified_purchase
    end

    def publish!
      update!(status: "published")
    end

    def hide!
      update!(status: "hidden")
    end

    def flag!
      increment!(:report_count)
      update!(status: "flagged") if report_count >= 3
    end

    def mark_helpful!
      increment!(:helpful_count)
    end

    def verify_purchase!
      return if is_verified_purchase

      has_purchase = installation.present? || agent_template.installations.where(account: account).exists?
      update!(is_verified_purchase: has_purchase, verified_at: Time.current) if has_purchase
    end

    private

    def update_template_rating
      agent_template.update_rating!
    end
  end
end

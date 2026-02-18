# frozen_string_literal: true

module Ai
  class PublisherAccount < ApplicationRecord
    self.table_name = "ai_publisher_accounts"

    # Associations
    belongs_to :account
    belongs_to :primary_user, class_name: "User", optional: true

    has_many :agent_templates, class_name: "Ai::AgentTemplate", foreign_key: :publisher_id, dependent: :destroy
    has_many :marketplace_transactions, class_name: "Ai::MarketplaceTransaction", foreign_key: :publisher_id, dependent: :destroy

    # Validations
    validates :publisher_name, presence: true
    validates :publisher_slug, presence: true, uniqueness: true,
              format: { with: /\A[a-z0-9-]+\z/, message: "only allows lowercase letters, numbers, and hyphens" }
    validates :status, presence: true, inclusion: { in: %w[pending active suspended terminated] }
    validates :verification_status, presence: true, inclusion: { in: %w[unverified pending verified rejected] }
    validates :revenue_share_percentage, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }

    # Scopes
    scope :active, -> { where(status: "active") }
    scope :verified, -> { where(verification_status: "verified") }
    scope :pending_verification, -> { where(verification_status: "pending") }

    # Callbacks
    before_validation :generate_slug, on: :create, if: -> { publisher_slug.blank? && publisher_name.present? }

    # Methods
    def verified?
      verification_status == "verified"
    end

    def active?
      status == "active"
    end

    def can_publish?
      active? && verified?
    end

    def calculate_payout(gross_amount)
      gross_amount * (revenue_share_percentage / 100.0)
    end

    def record_earnings(amount)
      increment!(:lifetime_earnings_usd, amount)
      increment!(:pending_payout_usd, amount)
    end

    def process_payout(amount)
      return false if amount > pending_payout_usd

      decrement!(:pending_payout_usd, amount)
      update!(last_payout_at: Time.current)
      true
    end

    private

    def generate_slug
      self.publisher_slug = publisher_name.parameterize
    end
  end
end

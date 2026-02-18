# frozen_string_literal: true

module Ai
  class MarketplaceTransaction < ApplicationRecord
    self.table_name = "ai_marketplace_transactions"

    # Associations
    belongs_to :account
    belongs_to :publisher, class_name: "Ai::PublisherAccount"
    belongs_to :agent_template, class_name: "Ai::AgentTemplate"
    belongs_to :installation, class_name: "Ai::AgentInstallation", optional: true

    # Validations
    validates :transaction_type, presence: true, inclusion: { in: %w[purchase subscription renewal refund payout] }
    validates :status, presence: true, inclusion: { in: %w[pending completed failed refunded disputed] }
    validates :gross_amount_usd, presence: true, numericality: { greater_than_or_equal_to: 0 }
    validates :commission_amount_usd, presence: true, numericality: { greater_than_or_equal_to: 0 }
    validates :publisher_amount_usd, presence: true, numericality: { greater_than_or_equal_to: 0 }
    validates :commission_percentage, presence: true, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }

    # Scopes
    scope :completed, -> { where(status: "completed") }
    scope :pending, -> { where(status: "pending") }
    scope :purchases, -> { where(transaction_type: "purchase") }
    scope :subscriptions, -> { where(transaction_type: "subscription") }
    scope :refunds, -> { where(transaction_type: "refund") }
    scope :payouts, -> { where(transaction_type: "payout") }
    scope :for_period, ->(start_date, end_date) { where(created_at: start_date..end_date) }

    # Callbacks
    before_validation :calculate_amounts, on: :create

    # Methods
    def completed?
      status == "completed"
    end

    def complete!
      return false unless status == "pending"

      transaction do
        update!(status: "completed", completed_at: Time.current)
        publisher.record_earnings(publisher_amount_usd) if transaction_type.in?(%w[purchase subscription renewal])
      end
    end

    def refund!
      return false unless completed? && transaction_type.in?(%w[purchase subscription renewal])

      update!(status: "refunded")
      # Create a refund transaction record
      self.class.create!(
        account: account,
        publisher: publisher,
        agent_template: agent_template,
        installation: installation,
        transaction_type: "refund",
        status: "completed",
        gross_amount_usd: -gross_amount_usd,
        commission_amount_usd: -commission_amount_usd,
        publisher_amount_usd: -publisher_amount_usd,
        commission_percentage: commission_percentage,
        completed_at: Time.current
      )
    end

    def dispute!
      update!(status: "disputed") if completed?
    end

    private

    def calculate_amounts
      return if commission_percentage.blank? || gross_amount_usd.blank?

      self.commission_amount_usd ||= gross_amount_usd * (commission_percentage / 100.0)
      self.publisher_amount_usd ||= gross_amount_usd - commission_amount_usd
    end
  end
end

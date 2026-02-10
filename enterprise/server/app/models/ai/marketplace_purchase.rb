# frozen_string_literal: true

module Ai
  class MarketplacePurchase < ApplicationRecord
    self.table_name = "ai_marketplace_purchases"

    # Associations
    belongs_to :account
    belongs_to :user, optional: true
    belongs_to :agent_template, class_name: "Ai::AgentTemplate"
    belongs_to :installation, class_name: "Ai::AgentInstallation", optional: true

    # Validations
    validates :purchase_type, presence: true, inclusion: { in: %w[one_time subscription credit upgrade] }
    validates :status, presence: true, inclusion: { in: %w[pending processing completed failed refunded cancelled] }
    validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }
    validates :final_price, presence: true, numericality: { greater_than_or_equal_to: 0 }
    validates :currency, presence: true

    # Scopes
    scope :pending, -> { where(status: "pending") }
    scope :completed, -> { where(status: "completed") }
    scope :failed, -> { where(status: "failed") }
    scope :refunded, -> { where(is_refunded: true) }
    scope :for_period, ->(start_date, end_date) { where(created_at: start_date..end_date) }
    scope :recent, -> { order(created_at: :desc) }

    # Callbacks
    before_validation :calculate_final_price, on: :create
    after_commit :record_marketplace_transaction, on: :create, if: :completed?

    # Instance methods
    def pending?
      status == "pending"
    end

    def completed?
      status == "completed"
    end

    def failed?
      status == "failed"
    end

    def can_refund?
      completed? && !is_refunded && paid_at && paid_at > 30.days.ago
    end

    def process_payment!(payment_reference)
      return false unless pending?

      transaction do
        update!(
          status: "processing"
        )

        # Process the payment (would integrate with payment service)
        # For now, mark as completed
        complete!(payment_reference)
      end
    end

    def complete!(payment_reference)
      return false unless status.in?(%w[pending processing])

      transaction do
        update!(
          status: "completed",
          payment_reference: payment_reference,
          paid_at: Time.current
        )

        # Create the installation if not exists
        create_installation! unless installation.present?

        # Record the transaction
        record_marketplace_transaction
      end

      true
    end

    def fail!(reason = nil)
      update!(
        status: "failed",
        metadata: metadata.merge(failure_reason: reason)
      )
    end

    def refund!(reason: nil, amount: nil)
      return { success: false, error: "Cannot refund this purchase" } unless can_refund?

      refund_amount = amount || final_price

      transaction do
        update!(
          is_refunded: true,
          refund_amount: refund_amount,
          refunded_at: Time.current,
          refund_reason: reason,
          status: "refunded"
        )

        # Create refund transaction
        Ai::MarketplaceTransaction.create!(
          account: account,
          publisher: agent_template.publisher,
          agent_template: agent_template,
          installation: installation,
          transaction_type: "refund",
          status: "completed",
          gross_amount_usd: -refund_amount,
          commission_percentage: agent_template.publisher.revenue_share_percentage,
          commission_amount_usd: -(refund_amount * (100 - agent_template.publisher.revenue_share_percentage) / 100.0),
          publisher_amount_usd: -(refund_amount * agent_template.publisher.revenue_share_percentage / 100.0)
        )

        # Deactivate installation if full refund
        if refund_amount >= final_price && installation
          installation.cancel!
        end
      end

      { success: true, refund_amount: refund_amount }
    end

    def summary
      {
        id: id,
        template_name: agent_template.name,
        purchase_type: purchase_type,
        status: status,
        price: price,
        discount_amount: discount_amount,
        final_price: final_price,
        currency: currency,
        payment_method: payment_method,
        paid_at: paid_at,
        is_refunded: is_refunded,
        refund_amount: refund_amount,
        created_at: created_at
      }
    end

    private

    def calculate_final_price
      self.final_price = price - (discount_amount || 0)
    end

    def create_installation!
      inst = Ai::AgentInstallation.create!(
        account: account,
        agent_template: agent_template,
        installed_by: user,
        status: "active",
        license_type: purchase_type == "subscription" ? "standard" : "perpetual"
      )

      update!(installation: inst)
    end

    def record_marketplace_transaction
      return unless completed?

      publisher = agent_template.publisher
      commission_rate = 100 - publisher.revenue_share_percentage
      commission = final_price * (commission_rate / 100.0)
      publisher_amount = final_price - commission

      Ai::MarketplaceTransaction.create!(
        account: account,
        publisher: publisher,
        agent_template: agent_template,
        installation: installation,
        transaction_type: "purchase",
        status: "completed",
        gross_amount_usd: final_price,
        commission_percentage: commission_rate,
        commission_amount_usd: commission,
        publisher_amount_usd: publisher_amount,
        metadata: { purchase_id: id }
      )

      # Update publisher earnings
      publisher.record_earnings(publisher_amount)
    end
  end
end

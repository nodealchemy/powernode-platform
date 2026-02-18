# frozen_string_literal: true

class ResellerPayout < ApplicationRecord
  # Associations
  belongs_to :reseller
  belongs_to :processed_by, class_name: "User", optional: true

  has_many :commissions, class_name: "ResellerCommission", foreign_key: :payout_id, dependent: :nullify

  # Validations
  validates :payout_reference, presence: true, uniqueness: true
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :fee, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :net_amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :currency, presence: true
  validates :status, presence: true, inclusion: { in: %w[pending processing completed failed cancelled] }
  validates :payout_method, presence: true, inclusion: { in: %w[bank_transfer paypal stripe check wire] }
  validates :requested_at, presence: true

  # Scopes
  scope :pending, -> { where(status: "pending") }
  scope :processing, -> { where(status: "processing") }
  scope :completed, -> { where(status: "completed") }
  scope :failed, -> { where(status: "failed") }
  scope :for_period, ->(start_date, end_date) { where(requested_at: start_date..end_date) }

  # Instance methods
  def pending?
    status == "pending"
  end

  def processing?
    status == "processing"
  end

  def completed?
    status == "completed"
  end

  def failed?
    status == "failed"
  end

  def can_process?
    pending?
  end

  def start_processing!(processed_by_user)
    return false unless can_process?

    update!(
      status: "processing",
      processed_by: processed_by_user,
      processed_at: Time.current
    )
  end

  def complete!(provider_reference: nil)
    return false unless processing?

    transaction do
      update!(
        status: "completed",
        provider_reference: provider_reference,
        completed_at: Time.current
      )

      # Mark associated commissions as paid
      available_commissions.find_each do |commission|
        commission.mark_paid!(self)
      end

      # Update reseller totals
      reseller.increment!(:total_paid_out, amount)
    end
  end

  def fail!(reason)
    return false unless processing?

    transaction do
      update!(
        status: "failed",
        failure_reason: reason,
        failed_at: Time.current
      )

      # Return the amount to pending payout
      reseller.increment!(:pending_payout, amount)
    end
  end

  def cancel!(reason: nil)
    return false unless pending?

    transaction do
      update!(
        status: "cancelled",
        metadata: metadata.merge(cancellation_reason: reason)
      )

      # Return the amount to pending payout
      reseller.increment!(:pending_payout, amount)
    end
  end

  def retry!
    return false unless failed?

    update!(
      status: "pending",
      failure_reason: nil,
      failed_at: nil,
      processed_at: nil,
      processed_by: nil
    )

    # Deduct from pending payout again
    reseller.decrement!(:pending_payout, amount)
  end

  def available_commissions
    reseller.commissions.where(status: %w[pending available]).where("available_at <= ?", Time.current)
  end

  def summary
    {
      id: id,
      payout_reference: payout_reference,
      amount: amount,
      fee: fee,
      net_amount: net_amount,
      currency: currency,
      status: status,
      payout_method: payout_method,
      requested_at: requested_at,
      processed_at: processed_at,
      completed_at: completed_at,
      provider_reference: provider_reference
    }
  end
end

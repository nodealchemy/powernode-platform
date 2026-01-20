# frozen_string_literal: true

class ResellerCommission < ApplicationRecord
  # Associations
  belongs_to :reseller
  belongs_to :referred_account, class_name: "Account"
  belongs_to :payout, class_name: "ResellerPayout", optional: true

  # Validations
  validates :commission_type, presence: true, inclusion: { in: %w[signup_bonus recurring one_time upgrade_bonus] }
  validates :source_type, presence: true, inclusion: { in: %w[subscription payment credit_purchase plan_upgrade] }
  validates :gross_amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :commission_percentage, presence: true, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :commission_amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :status, presence: true, inclusion: { in: %w[pending available paid cancelled clawed_back] }
  validates :earned_at, presence: true

  # Scopes
  scope :pending, -> { where(status: "pending") }
  scope :available, -> { where(status: "available") }
  scope :paid, -> { where(status: "paid") }
  scope :unpaid, -> { where(status: %w[pending available]) }
  scope :by_type, ->(type) { where(commission_type: type) }
  scope :for_period, ->(start_date, end_date) { where(earned_at: start_date..end_date) }
  scope :now_available, -> { where("available_at <= ?", Time.current).where(status: "pending") }

  # Callbacks
  after_create :update_referral_stats

  # Instance methods
  def pending?
    status == "pending"
  end

  def available?
    status == "available"
  end

  def paid?
    status == "paid"
  end

  def can_be_paid?
    available? || (pending? && available_at && available_at <= Time.current)
  end

  def make_available!
    return false unless pending? && available_at && available_at <= Time.current

    update!(status: "available")
  end

  def mark_paid!(payout_record)
    return false unless can_be_paid?

    update!(
      status: "paid",
      payout: payout_record,
      paid_at: Time.current
    )
  end

  def cancel!(reason: nil)
    return false if paid?

    transaction do
      update!(status: "cancelled", metadata: metadata.merge(cancellation_reason: reason))

      # Reverse the pending payout
      reseller.decrement!(:pending_payout, commission_amount)
      reseller.decrement!(:lifetime_earnings, commission_amount)
    end
  end

  def claw_back!(reason: nil)
    return false unless paid?

    transaction do
      update!(status: "clawed_back", metadata: metadata.merge(clawback_reason: reason))

      # Create negative commission entry for tracking
      reseller.decrement!(:lifetime_earnings, commission_amount)
      reseller.decrement!(:total_paid_out, commission_amount)
    end
  end

  def days_until_available
    return 0 if available? || paid?
    return nil unless available_at

    [(available_at.to_date - Date.current).to_i, 0].max
  end

  private

  def update_referral_stats
    referral = reseller.referrals.find_by(referred_account: referred_account)
    return unless referral

    referral.increment!(:total_revenue, gross_amount)
    referral.increment!(:total_commission_earned, commission_amount)

    # Mark first payment if applicable
    if referral.first_payment_at.nil? && source_type == "payment"
      referral.update!(first_payment_at: Time.current)
    end
  end
end

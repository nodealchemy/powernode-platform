# frozen_string_literal: true

class ResellerReferral < ApplicationRecord
  # Associations
  belongs_to :reseller
  belongs_to :referred_account, class_name: "Account"

  # Validations
  validates :referral_code_used, presence: true
  validates :status, presence: true, inclusion: { in: %w[active churned cancelled] }
  validates :referred_at, presence: true
  validates :referred_account_id, uniqueness: true

  # Scopes
  scope :active, -> { where(status: "active") }
  scope :churned, -> { where(status: "churned") }
  scope :with_payments, -> { where.not(first_payment_at: nil) }
  scope :for_period, ->(start_date, end_date) { where(referred_at: start_date..end_date) }

  # Callbacks
  after_create :update_reseller_referral_counts
  after_update :update_reseller_referral_counts, if: :saved_change_to_status?
  after_destroy :decrement_reseller_referral_counts

  # Instance methods
  def active?
    status == "active"
  end

  def churned?
    status == "churned"
  end

  def mark_churned!
    return false unless active?

    transaction do
      update!(
        status: "churned",
        churned_at: Time.current
      )

      reseller.decrement!(:active_referrals, 1)
    end
  end

  def reactivate!
    return false unless churned?

    transaction do
      update!(
        status: "active",
        churned_at: nil
      )

      reseller.increment!(:active_referrals, 1)
    end
  end

  def cancel!
    return false if churned?

    transaction do
      update!(status: "cancelled")
      reseller.decrement!(:active_referrals, 1) if active?
      reseller.decrement!(:total_referrals, 1)
    end
  end

  def has_converted?
    first_payment_at.present?
  end

  def days_since_referral
    (Date.current - referred_at.to_date).to_i
  end

  def lifetime_value
    total_revenue
  end

  def summary
    {
      id: id,
      referred_account_id: referred_account_id,
      referred_account_name: referred_account&.name,
      referral_code_used: referral_code_used,
      status: status,
      total_revenue: total_revenue,
      total_commission_earned: total_commission_earned,
      referred_at: referred_at,
      first_payment_at: first_payment_at,
      churned_at: churned_at,
      has_converted: has_converted?,
      days_since_referral: days_since_referral
    }
  end

  private

  def update_reseller_referral_counts
    active_count = reseller.referrals.active.count
    total_count = reseller.referrals.count

    reseller.update_columns(
      active_referrals: active_count,
      total_referrals: total_count
    )
  end

  def decrement_reseller_referral_counts
    reseller.decrement!(:total_referrals, 1)
    reseller.decrement!(:active_referrals, 1) if active?
  end
end

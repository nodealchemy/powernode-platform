# frozen_string_literal: true

class Reseller < ApplicationRecord
  include Auditable

  # Associations
  belongs_to :account
  belongs_to :primary_user, class_name: "User"
  belongs_to :approved_by, class_name: "User", optional: true

  has_many :commissions, class_name: "ResellerCommission", dependent: :destroy
  has_many :payouts, class_name: "ResellerPayout", dependent: :destroy
  has_many :referrals, class_name: "ResellerReferral", dependent: :destroy
  has_many :referred_accounts, through: :referrals

  # Validations
  validates :company_name, presence: true, length: { minimum: 2, maximum: 200 }
  validates :contact_email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :referral_code, presence: true, uniqueness: true, length: { minimum: 4, maximum: 20 }
  validates :tier, presence: true, inclusion: { in: %w[bronze silver gold platinum] }
  validates :status, presence: true, inclusion: { in: %w[pending approved active suspended terminated] }
  validates :payout_method, inclusion: { in: %w[bank_transfer paypal stripe check wire] }, allow_nil: true
  validates :commission_percentage, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 50 }

  # Scopes
  scope :active, -> { where(status: "active") }
  scope :pending, -> { where(status: "pending") }
  scope :by_tier, ->(tier) { where(tier: tier) }
  scope :with_pending_payout, -> { where("pending_payout > ?", 0) }

  # Callbacks
  before_validation :generate_referral_code, on: :create, if: -> { referral_code.blank? }
  before_validation :set_commission_by_tier, on: :create

  # Constants for tier benefits
  TIER_BENEFITS = {
    "bronze" => { commission: 10.0, min_referrals: 0, revenue_threshold: 0 },
    "silver" => { commission: 15.0, min_referrals: 5, revenue_threshold: 5_000 },
    "gold" => { commission: 20.0, min_referrals: 15, revenue_threshold: 25_000 },
    "platinum" => { commission: 25.0, min_referrals: 50, revenue_threshold: 100_000 }
  }.freeze

  # Instance methods
  def active?
    status == "active"
  end

  def pending?
    status == "pending"
  end

  def can_receive_payouts?
    active? && pending_payout >= minimum_payout_amount
  end

  def minimum_payout_amount
    50.0 # Minimum $50 for payout
  end

  def approve!(approved_by_user)
    return false unless pending?

    update!(
      status: "approved",
      approved_by: approved_by_user,
      approved_at: Time.current
    )
  end

  def activate!
    return false unless status == "approved"

    update!(
      status: "active",
      activated_at: Time.current
    )
  end

  def suspend!(reason: nil)
    return false if terminated?

    update!(status: "suspended")
  end

  def terminate!
    update!(status: "terminated")
  end

  def terminated?
    status == "terminated"
  end

  def suspended?
    status == "suspended"
  end

  def eligible_for_tier_upgrade?
    next_tier = next_tier_name
    return false unless next_tier

    benefits = TIER_BENEFITS[next_tier]
    active_referrals >= benefits[:min_referrals] &&
      total_revenue_generated >= benefits[:revenue_threshold]
  end

  def next_tier_name
    case tier
    when "bronze" then "silver"
    when "silver" then "gold"
    when "gold" then "platinum"
    else nil
    end
  end

  def upgrade_tier!
    next_tier = next_tier_name
    return false unless next_tier && eligible_for_tier_upgrade?

    update!(
      tier: next_tier,
      commission_percentage: TIER_BENEFITS[next_tier][:commission]
    )
  end

  def record_commission(amount:, referred_account:, source_type:, source_id:, commission_type: "recurring")
    commission_amount = amount * (commission_percentage / 100.0)

    commission = commissions.create!(
      referred_account: referred_account,
      commission_type: commission_type,
      source_type: source_type,
      source_id: source_id,
      gross_amount: amount,
      commission_percentage: commission_percentage,
      commission_amount: commission_amount,
      earned_at: Time.current,
      available_at: Time.current + 30.days # 30-day hold period
    )

    # Update totals
    increment!(:lifetime_earnings, commission_amount)
    increment!(:pending_payout, commission_amount)
    increment!(:total_revenue_generated, amount)

    commission
  end

  def request_payout(amount:)
    return { success: false, error: "Amount exceeds available payout" } if amount > pending_payout
    return { success: false, error: "Minimum payout is $#{minimum_payout_amount}" } if amount < minimum_payout_amount
    return { success: false, error: "Account not active" } unless active?

    payout = payouts.create!(
      payout_reference: generate_payout_reference,
      amount: amount,
      fee: calculate_payout_fee(amount),
      net_amount: amount - calculate_payout_fee(amount),
      payout_method: payout_method,
      requested_at: Time.current,
      payout_details: payout_details
    )

    decrement!(:pending_payout, amount)

    { success: true, payout: payout }
  end

  def tier_benefits
    TIER_BENEFITS[tier]
  end

  def dashboard_stats
    {
      tier: tier,
      commission_percentage: commission_percentage,
      lifetime_earnings: lifetime_earnings,
      pending_payout: pending_payout,
      total_paid_out: total_paid_out,
      total_referrals: total_referrals,
      active_referrals: active_referrals,
      total_revenue_generated: total_revenue_generated,
      next_tier: next_tier_name,
      eligible_for_upgrade: eligible_for_tier_upgrade?,
      can_request_payout: can_receive_payouts?
    }
  end

  private

  def generate_referral_code
    loop do
      code = "#{company_name.parameterize[0..5].upcase}#{SecureRandom.hex(3).upcase}"
      self.referral_code = code
      break unless Reseller.exists?(referral_code: code)
    end
  end

  def set_commission_by_tier
    # Always set commission based on tier on create (overrides DB default)
    self.commission_percentage = TIER_BENEFITS[tier][:commission]
  end

  def generate_payout_reference
    "PO-#{Time.current.strftime('%Y%m')}-#{SecureRandom.hex(4).upcase}"
  end

  def calculate_payout_fee(amount)
    case payout_method
    when "paypal" then [ amount * 0.02, 25.0 ].min # 2% up to $25
    when "wire" then 25.0 # Flat $25 for wire
    else 0.0 # Free for bank transfer, check
    end
  end
end

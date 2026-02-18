# frozen_string_literal: true

class ResellerService
  attr_reader :account, :user

  def initialize(account:, user:)
    @account = account
    @user = user
  end

  # Apply for reseller program
  def apply(params)
    return { success: false, error: "Account already has a reseller profile" } if account.reseller.present?

    reseller = Reseller.new(
      account: account,
      primary_user: user,
      company_name: params[:company_name],
      contact_email: params[:contact_email] || user.email,
      contact_phone: params[:contact_phone],
      website_url: params[:website_url],
      tax_id: params[:tax_id],
      payout_method: params[:payout_method] || "bank_transfer",
      payout_details: params[:payout_details] || {}
    )

    if reseller.save
      Rails.logger.info "Reseller application submitted: Account #{account.id}, Reseller #{reseller.id}"
      { success: true, reseller: reseller }
    else
      { success: false, errors: reseller.errors.full_messages }
    end
  end

  # Track a new referral
  def track_referral(referred_account:, referral_code:)
    reseller = Reseller.find_by(referral_code: referral_code)
    return { success: false, error: "Invalid referral code" } unless reseller
    return { success: false, error: "Reseller is not active" } unless reseller.active?
    return { success: false, error: "Account already referred" } if ResellerReferral.exists?(referred_account: referred_account)
    return { success: false, error: "Cannot self-refer" } if referred_account == reseller.account

    referral = reseller.referrals.create!(
      referred_account: referred_account,
      referral_code_used: referral_code,
      referred_at: Time.current
    )

    # Create signup bonus commission
    reseller.record_commission(
      amount: signup_bonus_amount,
      referred_account: referred_account,
      source_type: "subscription",
      source_id: nil,
      commission_type: "signup_bonus"
    )

    Rails.logger.info "Referral tracked: Reseller #{reseller.id}, Referred Account #{referred_account.id}"
    { success: true, referral: referral }
  end

  # Record commission for a payment
  def record_payment_commission(payment:)
    referred_account = payment.account
    referral = ResellerReferral.find_by(referred_account: referred_account, status: "active")
    return { success: false, error: "No active referral found" } unless referral

    reseller = referral.reseller
    return { success: false, error: "Reseller is not active" } unless reseller.active?

    commission = reseller.record_commission(
      amount: payment.amount_cents / 100.0, # Convert cents to dollars
      referred_account: referred_account,
      source_type: "payment",
      source_id: payment.id,
      commission_type: "recurring"
    )

    Rails.logger.info "Commission recorded: Reseller #{reseller.id}, Payment #{payment.id}, Amount #{commission.commission_amount}"
    { success: true, commission: commission }
  end

  # Process payout request
  def request_payout(reseller:, amount:)
    unless user_can_manage_reseller?(reseller)
      return { success: false, error: "Not authorized to manage this reseller" }
    end

    result = reseller.request_payout(amount: amount)

    if result[:success]
      Rails.logger.info "Payout requested: Reseller #{reseller.id}, Amount #{amount}"
      # Queue payout processing job
      # WorkerJobService.enqueue_job("ResellerPayoutJob", args: [result[:payout].id])
    end

    result
  end

  # Admin: Approve reseller application
  def approve_application(reseller:)
    unless can_approve?
      return { success: false, error: "Not authorized to approve applications" }
    end

    return { success: false, error: "Reseller is not pending" } unless reseller.pending?

    if reseller.approve!(user)
      Rails.logger.info "Reseller approved: #{reseller.id} by User #{user.id}"
      { success: true, reseller: reseller }
    else
      { success: false, errors: reseller.errors.full_messages }
    end
  end

  # Admin: Activate approved reseller
  def activate_reseller(reseller:)
    unless can_approve?
      return { success: false, error: "Not authorized to activate resellers" }
    end

    if reseller.activate!
      Rails.logger.info "Reseller activated: #{reseller.id}"
      { success: true, reseller: reseller }
    else
      { success: false, error: "Could not activate reseller" }
    end
  end

  # Admin: Process payout
  def process_payout(payout:)
    unless can_process_payouts?
      return { success: false, error: "Not authorized to process payouts" }
    end

    return { success: false, error: "Payout cannot be processed" } unless payout.can_process?

    payout.start_processing!(user)

    # Simulate payment processing (in production, integrate with payment provider)
    begin
      provider_reference = process_payment_with_provider(payout)
      payout.complete!(provider_reference: provider_reference)

      Rails.logger.info "Payout completed: #{payout.id}, Reference: #{provider_reference}"
      { success: true, payout: payout }
    rescue StandardError => e
      payout.fail!(e.message)
      Rails.logger.error "Payout failed: #{payout.id}, Error: #{e.message}"
      { success: false, error: e.message }
    end
  end

  # Get dashboard statistics
  def dashboard_stats(reseller:)
    unless user_can_view_reseller?(reseller)
      return { success: false, error: "Not authorized to view this reseller" }
    end

    stats = reseller.dashboard_stats

    # Add recent activity
    stats[:recent_commissions] = reseller.commissions
                                         .order(earned_at: :desc)
                                         .limit(10)
                                         .map { |c| commission_summary(c) }

    stats[:recent_referrals] = reseller.referrals
                                       .order(referred_at: :desc)
                                       .limit(10)
                                       .map(&:summary)

    stats[:pending_payouts] = reseller.payouts
                                      .where(status: %w[pending processing])
                                      .map(&:summary)

    # Monthly trends
    stats[:monthly_earnings] = monthly_earnings(reseller)

    { success: true, stats: stats }
  end

  # List all resellers (admin)
  def list_resellers(filters: {})
    resellers = Reseller.all

    resellers = resellers.where(status: filters[:status]) if filters[:status].present?
    resellers = resellers.where(tier: filters[:tier]) if filters[:tier].present?

    resellers.includes(:account, :primary_user).order(created_at: :desc)
  end

  private

  def signup_bonus_amount
    25.0 # $25 signup bonus
  end

  def user_can_manage_reseller?(reseller)
    reseller.account == account || user.has_permission?("resellers.manage")
  end

  def user_can_view_reseller?(reseller)
    reseller.account == account || user.has_permission?("resellers.read")
  end

  def can_approve?
    user.has_permission?("resellers.manage")
  end

  def can_process_payouts?
    user.has_permission?("resellers.payouts")
  end

  def process_payment_with_provider(payout)
    # In production, integrate with Stripe Connect, PayPal Payouts, etc.
    # This is a placeholder that generates a reference
    "PROV-#{SecureRandom.hex(8).upcase}"
  end

  def commission_summary(commission)
    {
      id: commission.id,
      commission_type: commission.commission_type,
      source_type: commission.source_type,
      gross_amount: commission.gross_amount,
      commission_percentage: commission.commission_percentage,
      commission_amount: commission.commission_amount,
      status: commission.status,
      earned_at: commission.earned_at,
      available_at: commission.available_at,
      days_until_available: commission.days_until_available
    }
  end

  def monthly_earnings(reseller)
    reseller.commissions
            .where("earned_at >= ?", 12.months.ago)
            .group("DATE_TRUNC('month', earned_at)")
            .sum(:commission_amount)
            .transform_keys { |k| k.strftime("%Y-%m") }
  end
end

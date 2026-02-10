export interface Reseller {
  id: string;
  company_name: string;
  contact_email: string;
  contact_phone?: string;
  website_url?: string;
  referral_code: string;
  tier: ResellerTier;
  status: ResellerStatus;
  commission_percentage: number;
  lifetime_earnings: number;
  pending_payout: number;
  total_paid_out: number;
  total_referrals: number;
  active_referrals: number;
  total_revenue_generated: number;
  payout_method?: PayoutMethod;
  tier_benefits?: TierBenefits;
  eligible_for_upgrade: boolean;
  next_tier?: ResellerTier;
  can_request_payout: boolean;
  branding?: Record<string, unknown>;
  created_at: string;
  activated_at?: string;
}

export type ResellerTier = 'bronze' | 'silver' | 'gold' | 'platinum';
export type ResellerStatus = 'pending' | 'approved' | 'active' | 'suspended' | 'terminated';
export type PayoutMethod = 'bank_transfer' | 'paypal' | 'stripe' | 'check' | 'wire';

export interface TierBenefits {
  commission: number;
  min_referrals: number;
  revenue_threshold: number;
}

export interface ResellerCommission {
  id: string;
  commission_type: CommissionType;
  source_type: CommissionSourceType;
  gross_amount: number;
  commission_percentage: number;
  commission_amount: number;
  status: CommissionStatus;
  earned_at: string;
  available_at?: string;
  paid_at?: string;
  days_until_available?: number;
}

export type CommissionType = 'signup_bonus' | 'recurring' | 'one_time' | 'upgrade_bonus';
export type CommissionSourceType = 'subscription' | 'payment' | 'credit_purchase' | 'plan_upgrade';
export type CommissionStatus = 'pending' | 'available' | 'paid' | 'cancelled' | 'clawed_back';

export interface ResellerPayout {
  id: string;
  payout_reference: string;
  amount: number;
  fee: number;
  net_amount: number;
  currency: string;
  status: PayoutStatus;
  payout_method: PayoutMethod;
  requested_at: string;
  processed_at?: string;
  completed_at?: string;
  provider_reference?: string;
}

export type PayoutStatus = 'pending' | 'processing' | 'completed' | 'failed' | 'cancelled';

export interface ResellerReferral {
  id: string;
  referred_account_id: string;
  referred_account_name?: string;
  referral_code_used: string;
  status: ReferralStatus;
  total_revenue: number;
  total_commission_earned: number;
  referred_at: string;
  first_payment_at?: string;
  churned_at?: string;
  has_converted: boolean;
  days_since_referral: number;
}

export type ReferralStatus = 'active' | 'churned' | 'cancelled';

export interface ResellerDashboardStats {
  tier: ResellerTier;
  commission_percentage: number;
  lifetime_earnings: number;
  pending_payout: number;
  total_paid_out: number;
  total_referrals: number;
  active_referrals: number;
  total_revenue_generated: number;
  next_tier?: ResellerTier;
  eligible_for_upgrade: boolean;
  can_request_payout: boolean;
  recent_commissions: ResellerCommission[];
  recent_referrals: ResellerReferral[];
  pending_payouts: ResellerPayout[];
  monthly_earnings: Record<string, number>;
}

export interface ResellerApplicationData {
  company_name: string;
  contact_email: string;
  contact_phone?: string;
  website_url?: string;
  tax_id?: string;
  payout_method?: PayoutMethod;
  payout_details?: Record<string, unknown>;
}

export interface TierInfo {
  tier: ResellerTier;
  commission_percentage: number;
  min_referrals: number;
  revenue_threshold: number;
}

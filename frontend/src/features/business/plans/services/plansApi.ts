import { api } from '@/shared/services/api';

// Types for plans data
export interface Plan {
  id: string;
  name: string;
  description: string;
  price_cents: number;
  currency: string;
  billing_cycle: 'monthly' | 'yearly' | 'quarterly';
  status: 'active' | 'inactive' | 'archived';
  trial_days: number;
  is_public: boolean;
  formatted_price: string;
  monthly_price: string;
  subscription_count?: number; // Optional for public plans
  active_subscription_count?: number; // Optional for public plans
  can_be_deleted?: boolean; // Optional for basic plan listing
  // Discount fields (included in public plans API)
  has_annual_discount?: boolean;
  annual_discount_percent?: number;
  has_promotional_discount?: boolean;
  promotional_discount_percent?: number;
  promotional_discount_start?: string | null;
  promotional_discount_end?: string | null;
  promotional_discount_code?: string | null;
  has_volume_discount?: boolean;
  volume_discount_tiers?: VolumeDiscountTier[];
  annual_savings_amount?: string;
  annual_savings_percentage?: number;
  // Features and limits for plan comparison
  features?: Record<string, any>;
  limits?: Record<string, any>;
  created_at: string;
  updated_at: string;
}

export interface VolumeDiscountTier {
  min_quantity: number;
  discount_percent: number;
}

export interface DetailedPlan extends Plan {
  features: Record<string, any>;
  limits: Record<string, any>;
  default_role: string;
  metadata: Record<string, any>;
  stripe_price_id: string | null;
  paypal_plan_id: string | null;
  can_be_deleted: boolean;
  // Discount fields
  has_annual_discount: boolean;
  annual_discount_percent: number;
  has_volume_discount: boolean;
  volume_discount_tiers: VolumeDiscountTier[];
  has_promotional_discount: boolean;
  promotional_discount_percent: number;
  promotional_discount_start: string | null;
  promotional_discount_end: string | null;
  promotional_discount_code: string | null;
  annual_savings_amount: string;
  annual_savings_percentage: number;
}

export interface PlanFormData {
  name: string;
  description: string;
  price_cents: number;
  currency: string;
  billing_cycle: 'monthly' | 'yearly' | 'quarterly';
  status: 'active' | 'inactive' | 'archived';
  trial_days: number;
  is_public: boolean;
  features: Record<string, any>;
  limits: Record<string, any>;
  default_role: string;
  metadata: Record<string, any>;
  stripe_price_id?: string;
  paypal_plan_id?: string;
  // Discount fields
  has_annual_discount: boolean;
  annual_discount_percent: number;
  has_volume_discount: boolean;
  volume_discount_tiers: VolumeDiscountTier[];
  has_promotional_discount: boolean;
  promotional_discount_percent: number;
  promotional_discount_start: string;
  promotional_discount_end: string;
  promotional_discount_code: string;
}

export interface PlansListResponse {
  success: boolean;
  data: {
    plans: Plan[];
    total_count: number;
  };
}

export interface PlanResponse {
  success: boolean;
  data: {
    plan: DetailedPlan;
  };
}

export interface PlanCreateResponse {
  success: boolean;
  data: {
    plan: DetailedPlan;
    message: string;
  };
}

export interface PlanUpdateResponse {
  success: boolean;
  data: {
    plan: DetailedPlan;
    message: string;
  };
}

export interface PlansStatusResponse {
  success: boolean;
  data: {
    has_plans: boolean;
    total_count: number;
    active_count: number;
    public_count: number;
  };
}

class PlansApiService {
  // Get plans status (for dashboard setup check)
  async getStatus(): Promise<PlansStatusResponse> {
    const response = await api.get('/plans/status');
    return response.data;
  }

  // Get all plans
  async getPlans(): Promise<PlansListResponse> {
    const response = await api.get('/plans');
    return response.data;
  }

  // Get public plans (no auth required - for registration)
  async getPublicPlans(): Promise<PlansListResponse> {
    const response = await api.get('/public/plans');
    return response.data;
  }

  // Get a specific plan
  async getPlan(plan_id: string): Promise<PlanResponse> {
    const response = await api.get(`/plans/${plan_id}`);
    return response.data;
  }

  // Create a new plan
  async createPlan(planData: PlanFormData): Promise<PlanCreateResponse> {
    const response = await api.post('/plans', {
      plan: planData
    });
    return response.data;
  }

  // Update an existing plan
  async updatePlan(plan_id: string, planData: Partial<PlanFormData>): Promise<PlanUpdateResponse> {
    const response = await api.put(`/plans/${plan_id}`, {
      plan: planData
    });
    return response.data;
  }

  // Delete a plan
  async deletePlan(plan_id: string): Promise<{ success: boolean; message: string }> {
    const response = await api.delete(`/plans/${plan_id}`);
    return response.data;
  }

  // Duplicate a plan
  async duplicatePlan(plan_id: string): Promise<PlanCreateResponse> {
    const response = await api.post(`/plans/${plan_id}/duplicate`);
    return response.data;
  }

  // Toggle plan status (active/inactive)
  async togglePlanStatus(plan_id: string): Promise<PlanUpdateResponse> {
    const response = await api.put(`/plans/${plan_id}/toggle_status`);
    return response.data;
  }

  // Helper methods for plan data processing
  formatPrice(priceCents: number | null | undefined, currency: string): string {
    if (priceCents == null || priceCents === 0 || isNaN(priceCents)) {
      return 'Free';
    }
    
    const amount = priceCents / 100;
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: currency.toUpperCase()
    }).format(amount);
  }

  calculateMonthlyPrice(priceCents: number | null | undefined, currency: string, billingCycle: string): string {
    if (priceCents == null || priceCents === 0 || isNaN(priceCents)) {
      return 'Free';
    }
    
    let monthlyAmount = priceCents / 100;
    
    switch (billingCycle) {
      case 'quarterly':
        monthlyAmount = monthlyAmount / 3;
        break;
      case 'yearly':
        monthlyAmount = monthlyAmount / 12;
        break;
      default:
        // monthly already correct
        break;
    }

    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: currency.toUpperCase()
    }).format(monthlyAmount);
  }

  getBillingCycleLabel(cycle: string): string {
    switch (cycle) {
      case 'monthly':
        return 'Monthly';
      case 'quarterly':
        return 'Quarterly';
      case 'yearly':
        return 'Yearly';
      default:
        return cycle;
    }
  }

  // Default plan features for new plans
  getDefaultFeatures(): Record<string, boolean> {
    return {
      dashboard_access: true,
      basic_analytics: true,
      advanced_analytics: false,
      email_support: true,
      priority_support: false,
      api_access: false,
      custom_integrations: false,
      dedicated_support: false,
      global_analytics: false,
      system_administration: false,
      user_management: false,
      account_management: false,
      billing_management: false,
      platform_monitoring: false,
      security_administration: false
    };
  }

  // Default plan limits for new plans
  getDefaultLimits(): Record<string, number> {
    return {
      users: 5,
      projects: 10,
      storage_gb: 10,
      api_requests_per_month: 1000,
      accounts_managed: 1,
      global_access: 0 // 0 = false, 1 = true for boolean limits
    };
  }

  // Available currencies
  getAvailableCurrencies(): Array<{ value: string; label: string }> {
    return [
      { value: 'USD', label: 'US Dollar (USD)' },
      { value: 'EUR', label: 'Euro (EUR)' },
      { value: 'GBP', label: 'British Pound (GBP)' }
    ];
  }

  // Available billing cycles
  getAvailableBillingCycles(): Array<{ value: string; label: string }> {
    return [
      { value: 'monthly', label: 'Monthly' },
      { value: 'quarterly', label: 'Quarterly' },
      { value: 'yearly', label: 'Yearly' }
    ];
  }

  // Validate plan data
  validatePlanData(planData: Partial<PlanFormData>): string[] {
    const errors: string[] = [];

    if (!planData.name || planData.name.trim().length < 2) {
      errors.push('Plan name must be at least 2 characters long');
    }

    if (planData.price_cents === undefined || planData.price_cents < 0) {
      errors.push('Price must be 0 or greater');
    }

    if (!planData.currency || !['USD', 'EUR', 'GBP'].includes(planData.currency)) {
      errors.push('Currency must be USD, EUR, or GBP');
    }

    if (!planData.billing_cycle || !['monthly', 'quarterly', 'yearly'].includes(planData.billing_cycle)) {
      errors.push('Billing cycle must be monthly, quarterly, or yearly');
    }

    if (planData.trial_days !== undefined && (planData.trial_days < 0 || planData.trial_days > 365)) {
      errors.push('Trial days must be between 0 and 365');
    }

    return errors;
  }

  // Get status color classes for plan status badges
  getStatusColor(status: string): string {
    switch (status) {
      case 'active':
        return 'bg-theme-success text-theme-success border-theme-success';
      case 'inactive':
        return 'bg-theme-warning text-theme-warning border-theme-warning';
      case 'archived':
        return 'bg-theme-error text-theme-error border-theme-error';
      default:
        return 'bg-theme-background-secondary text-theme-secondary border-theme';
    }
  }
}

export const plansApi = new PlansApiService();
import { api } from './api';

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
  subscription_count: number;
  active_subscription_count: number;
  can_be_deleted?: boolean; // Optional for basic plan listing
  created_at: string;
  updated_at: string;
}

export interface DetailedPlan extends Plan {
  features: Record<string, any>;
  limits: Record<string, any>;
  default_roles: string[];
  metadata: Record<string, any>;
  stripe_price_id: string | null;
  paypal_plan_id: string | null;
  can_be_deleted: boolean;
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
  default_roles: string[];
  metadata: Record<string, any>;
  stripe_price_id?: string;
  paypal_plan_id?: string;
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

class PlansApiService {
  // Get all plans
  async getPlans(): Promise<PlansListResponse> {
    const response = await api.get('/plans');
    return response.data;
  }

  // Get a specific plan
  async getPlan(planId: string): Promise<PlanResponse> {
    const response = await api.get(`/plans/${planId}`);
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
  async updatePlan(planId: string, planData: Partial<PlanFormData>): Promise<PlanUpdateResponse> {
    const response = await api.put(`/plans/${planId}`, {
      plan: planData
    });
    return response.data;
  }

  // Delete a plan
  async deletePlan(planId: string): Promise<{ success: boolean; message: string }> {
    const response = await api.delete(`/plans/${planId}`);
    return response.data;
  }

  // Duplicate a plan
  async duplicatePlan(planId: string): Promise<PlanCreateResponse> {
    const response = await api.post(`/plans/${planId}/duplicate`);
    return response.data;
  }

  // Toggle plan status (active/inactive)
  async togglePlanStatus(planId: string): Promise<PlanUpdateResponse> {
    const response = await api.put(`/plans/${planId}/toggle_status`);
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

  getStatusColor(status: string): string {
    switch (status) {
      case 'active':
        return 'bg-green-100 text-green-800';
      case 'inactive':
        return 'bg-yellow-100 text-yellow-800';
      case 'archived':
        return 'bg-gray-100 text-gray-800';
      default:
        return 'bg-gray-100 text-gray-800';
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
}

export const plansApi = new PlansApiService();
import { api } from '@/shared/services/api';
import { isErrorWithResponse } from '@/shared/utils/errorHandling';

// Feature value types
export type FeatureValue = boolean | number | string | null;

// Types
export interface PlanFeature {
  id: string;
  name: string;
  description: string;
  type: 'boolean' | 'numeric' | 'text' | 'enum';
  category: 'core' | 'advanced' | 'integrations' | 'support' | 'analytics';
  default_value: FeatureValue;
  validation_rules?: {
    min?: number;
    max?: number;
    enum_values?: string[];
    required?: boolean;
    pattern?: string;
  };
  is_system_feature: boolean;
  created_at: string;
  updated_at: string;
}

export interface PlanLimit {
  id: string;
  plan_id: string;
  feature_id: string;
  value: FeatureValue;
  is_unlimited: boolean;
  is_enabled: boolean;
  custom_message?: string;
  created_at: string;
  updated_at: string;
  feature?: PlanFeature;
}

export interface Plan {
  id: string;
  name: string;
  slug: string;
  description: string;
  price_cents: number;
  billing_interval: 'monthly' | 'yearly';
  is_active: boolean;
  sort_order: number;
  trial_period_days?: number;
  limits: PlanLimit[];
  created_at: string;
  updated_at: string;
}

export interface PlanTemplate {
  id: string;
  name: string;
  description: string;
  features: Record<string, FeatureValue>;
  is_default: boolean;
}

export interface FeatureUsage {
  feature_id: string;
  current_usage: number;
  limit_value: number;
  is_unlimited: boolean;
  usage_percentage: number;
  is_approaching_limit: boolean;
  is_over_limit: boolean;
}

export interface PlanComparison {
  features: PlanFeature[];
  plans: Array<{
    plan: Plan;
    feature_values: Record<string, FeatureValue>;
  }>;
}

export interface FeatureFormData {
  name: string;
  description: string;
  type: 'boolean' | 'numeric' | 'text' | 'enum';
  category: 'core' | 'advanced' | 'integrations' | 'support' | 'analytics';
  default_value: FeatureValue;
  validation_rules?: {
    min?: number;
    max?: number;
    enum_values?: string[];
    required?: boolean;
    pattern?: string;
  };
}

export interface LimitFormData {
  value: FeatureValue;
  is_unlimited: boolean;
  is_enabled: boolean;
  custom_message?: string;
}

// API Service
export const planFeaturesApi = {
  // Features Management
  async getFeatures(): Promise<{ success: boolean; data?: PlanFeature[]; error?: string }> {
    try {
      const response = await api.get('/admin/plan_features');
      return response.data;
    } catch (error) {
      return {
        success: false,
        error: isErrorWithResponse(error) ? (error.response?.data?.error || 'Failed to fetch plan features') : 'Failed to fetch plan features'
      };
    }
  },

  async createFeature(featureData: FeatureFormData): Promise<{ success: boolean; data?: PlanFeature; message?: string; error?: string }> {
    try {
      const response = await api.post('/admin/plan_features', { feature: featureData });
      return response.data;
    } catch (error) {
      return {
        success: false,
        error: isErrorWithResponse(error) ? (error.response?.data?.error || 'Failed to create plan feature') : 'Failed to create plan feature'
      };
    }
  },

  async updateFeature(featureId: string, featureData: Partial<FeatureFormData>): Promise<{ success: boolean; data?: PlanFeature; message?: string; error?: string }> {
    try {
      const response = await api.put(`/admin/plan_features/${featureId}`, { feature: featureData });
      return response.data;
    } catch (error) {
      return {
        success: false,
        error: isErrorWithResponse(error) ? (error.response?.data?.error || 'Failed to update plan feature') : 'Failed to update plan feature'
      };
    }
  },

  async deleteFeature(featureId: string): Promise<{ success: boolean; message?: string; error?: string }> {
    try {
      const response = await api.delete(`/admin/plan_features/${featureId}`);
      return response.data;
    } catch (error) {
      return {
        success: false,
        error: isErrorWithResponse(error) ? (error.response?.data?.error || 'Failed to delete plan feature') : 'Failed to delete plan feature'
      };
    }
  },

  // Plans Management
  async getPlans(): Promise<{ success: boolean; data?: Plan[]; error?: string }> {
    try {
      const response = await api.get('/admin/plans');
      return response.data;
    } catch (error) {
      return {
        success: false,
        error: isErrorWithResponse(error) ? (error.response?.data?.error || 'Failed to fetch plans') : 'Failed to fetch plans'
      };
    }
  },

  async getPlan(planId: string): Promise<{ success: boolean; data?: Plan; error?: string }> {
    try {
      const response = await api.get(`/admin/plans/${planId}`);
      return response.data;
    } catch (error) {
      return {
        success: false,
        error: isErrorWithResponse(error) ? (error.response?.data?.error || 'Failed to fetch plan') : 'Failed to fetch plan'
      };
    }
  },

  // Plan Limits Management
  async updatePlanLimit(planId: string, featureId: string, limitData: LimitFormData): Promise<{ success: boolean; data?: PlanLimit; message?: string; error?: string }> {
    try {
      const response = await api.put(`/admin/plans/${planId}/limits/${featureId}`, { limit: limitData });
      return response.data;
    } catch (error) {
      return {
        success: false,
        error: isErrorWithResponse(error) ? (error.response?.data?.error || 'Failed to update plan limit') : 'Failed to update plan limit'
      };
    }
  },

  async bulkUpdateLimits(planId: string, limits: Record<string, LimitFormData>): Promise<{ success: boolean; data?: PlanLimit[]; message?: string; error?: string }> {
    try {
      const response = await api.put(`/admin/plans/${planId}/limits`, { limits });
      return response.data;
    } catch (error) {
      return {
        success: false,
        error: isErrorWithResponse(error) ? (error.response?.data?.error || 'Failed to bulk update plan limits') : 'Failed to bulk update plan limits'
      };
    }
  },

  // Plan Templates
  async getTemplates(): Promise<{ success: boolean; data?: PlanTemplate[]; error?: string }> {
    try {
      const response = await api.get('/admin/plan_templates');
      return response.data;
    } catch (error) {
      return {
        success: false,
        error: isErrorWithResponse(error) ? (error.response?.data?.error || 'Failed to fetch plan templates') : 'Failed to fetch plan templates'
      };
    }
  },

  async applyTemplate(planId: string, templateId: string): Promise<{ success: boolean; data?: Plan; message?: string; error?: string }> {
    try {
      const response = await api.post(`/admin/plans/${planId}/apply_template`, { template_id: templateId });
      return response.data;
    } catch (error) {
      return {
        success: false,
        error: isErrorWithResponse(error) ? (error.response?.data?.error || 'Failed to apply plan template') : 'Failed to apply plan template'
      };
    }
  },

  // Plan Comparison
  async getComparison(): Promise<{ success: boolean; data?: PlanComparison; error?: string }> {
    try {
      const response = await api.get('/admin/plans/comparison');
      return response.data;
    } catch (error) {
      return {
        success: false,
        error: isErrorWithResponse(error) ? (error.response?.data?.error || 'Failed to fetch plan comparison') : 'Failed to fetch plan comparison'
      };
    }
  },

  // Feature Usage Analytics
  async getFeatureUsage(accountId?: string): Promise<{ success: boolean; data?: FeatureUsage[]; error?: string }> {
    try {
      const params = accountId ? `?account_id=${accountId}` : '';
      const response = await api.get(`/admin/feature_usage${params}`);
      return response.data;
    } catch (error) {
      return {
        success: false,
        error: isErrorWithResponse(error) ? (error.response?.data?.error || 'Failed to fetch feature usage') : 'Failed to fetch feature usage'
      };
    }
  },

  // Validation
  async validateFeatureValue(featureId: string, value: FeatureValue): Promise<{ success: boolean; valid?: boolean; errors?: string[]; error?: string }> {
    try {
      const response = await api.post(`/admin/plan_features/${featureId}/validate`, { value });
      return response.data;
    } catch (error) {
      return {
        success: false,
        error: isErrorWithResponse(error) ? (error.response?.data?.error || 'Failed to validate feature value') : 'Failed to validate feature value'
      };
    }
  },

  // Helper methods
  getCategoryIcon(category: string): string {
    switch (category) {
      case 'core': return '⚡';
      case 'advanced': return '🚀';
      case 'integrations': return '🔗';
      case 'support': return '💬';
      case 'analytics': return '📊';
      default: return '⚙️';
    }
  },

  getCategoryColor(category: string): string {
    switch (category) {
      case 'core': return 'bg-theme-interactive-primary bg-opacity-10 text-theme-interactive-primary';
      case 'advanced': return 'bg-theme-success bg-opacity-10 text-theme-success';
      case 'integrations': return 'bg-theme-info bg-opacity-10 text-theme-info';
      case 'support': return 'bg-theme-warning bg-opacity-10 text-theme-warning';
      case 'analytics': return 'bg-theme-interactive-primary/10 text-theme-interactive-primary';
      default: return 'bg-theme-surface text-theme-secondary';
    }
  },

  getTypeIcon(type: string): string {
    switch (type) {
      case 'boolean': return '☑️';
      case 'numeric': return '🔢';
      case 'text': return '📝';
      case 'enum': return '📋';
      default: return '⚙️';
    }
  },

  formatFeatureValue(feature: PlanFeature, value: FeatureValue): string {
    if (value === null || value === undefined) return 'Not set';
    
    switch (feature.type) {
      case 'boolean':
        return value ? 'Enabled' : 'Disabled';
      case 'numeric':
        return typeof value === 'number' ? value.toLocaleString() : value.toString();
      case 'text':
        return value.toString();
      case 'enum':
        return value.toString();
      default:
        return value.toString();
    }
  },

  formatPrice(priceCents: number): string {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: 'USD',
    }).format(priceCents / 100);
  },

  getUsageStatusColor(usage: FeatureUsage): string {
    if (usage.is_over_limit) return 'text-theme-error';
    if (usage.is_approaching_limit) return 'text-theme-warning';
    return 'text-theme-success';
  },

  getUsageStatusIcon(usage: FeatureUsage): string {
    if (usage.is_over_limit) return '🚫';
    if (usage.is_approaching_limit) return '⚠️';
    return '✅';
  },

  validateFeatureFormData(data: FeatureFormData): string[] {
    const errors: string[] = [];

    if (!data.name || data.name.trim().length < 2) {
      errors.push('Feature name must be at least 2 characters long');
    }

    if (!data.description || data.description.trim().length < 10) {
      errors.push('Feature description must be at least 10 characters long');
    }

    if (!data.type) {
      errors.push('Feature type is required');
    }

    if (!data.category) {
      errors.push('Feature category is required');
    }

    if (data.type === 'numeric' && data.validation_rules) {
      const { min, max } = data.validation_rules;
      if (min !== undefined && max !== undefined && min >= max) {
        errors.push('Minimum value must be less than maximum value');
      }
    }

    if (data.type === 'enum' && (!data.validation_rules?.enum_values || data.validation_rules.enum_values.length === 0)) {
      errors.push('Enum type features must have at least one option');
    }

    return errors;
  },

  validateLimitFormData(feature: PlanFeature, data: LimitFormData): string[] {
    const errors: string[] = [];

    if (!data.is_unlimited && !data.is_enabled) {
      errors.push('Limit must be either unlimited or enabled with a value');
    }

    if (data.is_enabled && !data.is_unlimited) {
      if (feature.type === 'numeric') {
        const numValue = Number(data.value);
        if (isNaN(numValue)) {
          errors.push('Numeric features require a valid number');
        } else if (feature.validation_rules?.min !== undefined && numValue < feature.validation_rules.min) {
          errors.push(`Value must be at least ${feature.validation_rules.min}`);
        } else if (feature.validation_rules?.max !== undefined && numValue > feature.validation_rules.max) {
          errors.push(`Value must be at most ${feature.validation_rules.max}`);
        }
      }

      if (feature.type === 'enum' && feature.validation_rules?.enum_values) {
        if (!feature.validation_rules.enum_values.includes(String(data.value))) {
          errors.push('Value must be one of the allowed options');
        }
      }
    }

    return errors;
  },

  getDefaultFormData(): FeatureFormData {
    return {
      name: '',
      description: '',
      type: 'boolean',
      category: 'core',
      default_value: false,
      validation_rules: {}
    };
  },

  getDefaultLimitData(): LimitFormData {
    return {
      value: null,
      is_unlimited: false,
      is_enabled: true,
      custom_message: ''
    };
  }
};

export default planFeaturesApi;
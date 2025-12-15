import { Plan } from '@/features/plans/services/plansApi';

/**
 * Feature labels for better display
 */
export const featureLabels: { [key: string]: string } = {
  'community_access': 'Community Access',
  'core_features': 'Core Features',
  'dashboard_access': 'Dashboard Access',
  'mobile_responsive': 'Mobile Responsive',
  'email_notifications': 'Email Notifications',
  'basic_reporting': 'Basic Reporting',
  'standard_support': 'Standard Support',
  'basic_analytics': 'Basic Analytics',
  'email_support': 'Email Support',
  'advanced_analytics': 'Advanced Analytics',
  'priority_support': 'Priority Support',
  'api_access': 'API Access',
  'custom_branding': 'Custom Branding',
  'data_export': 'Data Export',
  'team_collaboration': 'Team Collaboration',
  'webhook_integrations': 'Webhook Integrations',
  'custom_fields': 'Custom Fields',
  'advanced_filters': 'Advanced Filters',
  'custom_integrations': 'Custom Integrations',
  'dedicated_support': 'Dedicated Support',
  'white_label': 'White Label Solution',
  'sso_integration': 'Single Sign-On (SSO)',
  'advanced_security': 'Advanced Security',
  'audit_logs': 'Audit Logs',
  'sla_guarantees': 'SLA Guarantees'
};

/**
 * Calculate plan price based on billing cycle
 */
export const calculatePlanPrice = (plan: Plan, cycle: 'monthly' | 'yearly'): string => {
  if (plan.price_cents === 0) return 'Free';

  let priceCents = plan.price_cents;

  // Apply discounts based on what badge is being shown (matches badge logic)
  if (cycle === 'yearly' && plan.billing_cycle === 'monthly' && plan.has_annual_discount) {
    // When viewing yearly, apply annual discount
    const discountPercent = plan.annual_discount_percent ? parseFloat(plan.annual_discount_percent.toString()) : 0;
    priceCents = priceCents * 12 * (1 - discountPercent / 100);
  } else if (cycle === 'monthly' && plan.billing_cycle === 'yearly') {
    priceCents = priceCents / 12;
  }

  const amount = priceCents / 100;
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: plan.currency
  }).format(amount);
};

/**
 * Get monthly price for a plan (used in comparison views)
 */
export const getMonthlyPrice = (plan: Plan, billingCycle: 'monthly' | 'yearly'): string => {
  if (plan.price_cents === 0) return 'Free';

  let monthlyCents = plan.price_cents;

  // Apply same discount logic as main price calculation for consistency
  if (billingCycle === 'yearly' && plan.billing_cycle === 'monthly' && plan.has_annual_discount) {
    // When viewing yearly billing, show monthly equivalent of discounted annual price
    const discountPercent = plan.annual_discount_percent ? parseFloat(plan.annual_discount_percent.toString()) : 0;
    const discountedAnnualPrice = monthlyCents * 12 * (1 - discountPercent / 100);
    monthlyCents = discountedAnnualPrice / 12;
  } else if (plan.billing_cycle === 'yearly') {
    monthlyCents = monthlyCents / 12;
  }

  const amount = monthlyCents / 100;
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: plan.currency
  }).format(amount);
};

/**
 * Check if a plan is popular (for featuring)
 */
export const isPlanPopular = (plan: Plan): boolean => {
  return plan.name.toLowerCase().includes('pro') || plan.name.toLowerCase().includes('standard');
};

/**
 * Get features for a plan
 */
export const getPlanFeatures = (plan: Plan): string[] => {
  // Use actual plan features if available, fallback to tier-based features
  if (plan.features && typeof plan.features === 'object' && Object.keys(plan.features).length > 0) {
    const enabledFeatures = Object.entries(plan.features)
      .filter(([key, enabled]) => enabled === true && !key.startsWith('max_') && !key.endsWith('_gb'))
      .map(([feature]) => featureLabels[feature] || feature.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase()))
      .sort();

    return enabledFeatures;
  }

  // Fallback to tier-based features if no features data
  const baseName = plan.name.toLowerCase();
  if (baseName.includes('free') || plan.price_cents === 0) {
    return [
      'Up to 5 projects',
      'Basic analytics',
      'Email support',
      'Community access'
    ];
  } else if (baseName.includes('pro') || baseName.includes('standard')) {
    return [
      'Unlimited projects',
      'Advanced analytics',
      'Priority support',
      'API access',
      'Custom integrations',
      'Team collaboration'
    ];
  } else if (baseName.includes('enterprise') || baseName.includes('business')) {
    return [
      'Everything in Pro',
      'Advanced security',
      'Custom SLA',
      'Dedicated support',
      'On-premise option',
      'Custom training'
    ];
  }
  return [
    'Core features',
    'Standard support',
    'Basic analytics'
  ];
};

/**
 * Get all unique features across all plans (for comparison)
 */
export const getAllPlanFeatures = (plans: Plan[]): string[] => {
  const allFeatures = new Set<string>();
  plans.forEach(plan => {
    getPlanFeatures(plan).forEach(feature => {
      allFeatures.add(feature);
    });
  });
  return Array.from(allFeatures).sort();
};

/**
 * Check if a plan has a specific feature
 */
export const planHasFeature = (plan: Plan, feature: string): boolean => {
  return getPlanFeatures(plan).includes(feature);
};

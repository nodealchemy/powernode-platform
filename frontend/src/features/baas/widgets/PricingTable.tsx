import React from 'react';

interface PricingPlan {
  id: string;
  name: string;
  description?: string;
  price: number;
  currency: string;
  interval: 'month' | 'year';
  features: string[];
  highlighted?: boolean;
  ctaText?: string;
}

interface PricingTableProps {
  plans: PricingPlan[];
  onSelectPlan?: (planId: string) => void;
  currentPlanId?: string;
  theme?: 'light' | 'dark';
}

const formatPrice = (price: number, currency: string): string => {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: currency.toUpperCase(),
    minimumFractionDigits: 0,
  }).format(price);
};

/**
 * Embeddable Pricing Table Widget
 *
 * This component can be embedded in external applications via iframe or web component.
 * It displays available pricing plans and allows users to select one.
 */
export const PricingTable: React.FC<PricingTableProps> = ({
  plans,
  onSelectPlan,
  currentPlanId,
  theme = 'light',
}) => {
  const isDark = theme === 'dark';

  const baseClasses = isDark
    ? 'bg-theme-background text-white'
    : 'bg-white text-theme-primary';

  const cardClasses = 'bg-theme-surface border-theme-border';

  const highlightClasses = isDark
    ? 'ring-2 ring-theme-info bg-theme-surface-alt'
    : 'ring-2 ring-theme-info shadow-lg';

  return (
    <div className={`p-6 ${baseClasses}`}>
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6 max-w-6xl mx-auto">
        {plans.map((plan) => (
          <div
            key={plan.id}
            className={`rounded-xl p-6 border transition-all ${cardClasses} ${
              plan.highlighted ? highlightClasses : ''
            }`}
          >
            {plan.highlighted && (
              <div className="text-center mb-4">
                <span className="px-3 py-1 bg-theme-info text-white text-xs font-medium rounded-full">
                  Most Popular
                </span>
              </div>
            )}

            <div className="text-center mb-6">
              <h3 className="text-xl font-bold mb-2">{plan.name}</h3>
              {plan.description && (
                <p className="text-sm text-theme-muted">
                  {plan.description}
                </p>
              )}
            </div>

            <div className="text-center mb-6">
              <span className="text-4xl font-bold">
                {formatPrice(plan.price, plan.currency)}
              </span>
              <span className="text-sm text-theme-muted">
                /{plan.interval}
              </span>
            </div>

            <ul className="space-y-3 mb-6">
              {plan.features.map((feature, index) => (
                <li key={index} className="flex items-start gap-2">
                  <svg
                    className="w-5 h-5 text-theme-success flex-shrink-0 mt-0.5"
                    fill="currentColor"
                    viewBox="0 0 20 20"
                  >
                    <path
                      fillRule="evenodd"
                      d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
                      clipRule="evenodd"
                    />
                  </svg>
                  <span className="text-sm text-theme-secondary">
                    {feature}
                  </span>
                </li>
              ))}
            </ul>

            <button
              onClick={() => onSelectPlan?.(plan.id)}
              disabled={currentPlanId === plan.id}
              className={`w-full py-3 px-4 rounded-lg font-medium transition-colors ${
                currentPlanId === plan.id
                  ? 'bg-theme-disabled text-theme-muted cursor-not-allowed'
                  : plan.highlighted
                  ? 'bg-theme-info text-white hover:bg-theme-info-hover'
                  : 'bg-theme-surface text-theme-primary hover:bg-theme-border'
              }`}
            >
              {currentPlanId === plan.id
                ? 'Current Plan'
                : plan.ctaText || 'Get Started'}
            </button>
          </div>
        ))}
      </div>
    </div>
  );
};

export default PricingTable;

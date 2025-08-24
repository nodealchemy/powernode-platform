import React from 'react';
import { Plan } from '@/features/plans/services/plansApi';
import { CheckIcon, ArrowRightIcon } from '@heroicons/react/24/outline';
import { StarIcon as StarSolidIcon } from '@heroicons/react/24/solid';

interface PlanCardProps {
  plan: Plan;
  billingCycle: 'monthly' | 'yearly';
  isSelected?: boolean;
  isPopular?: boolean;
  onSelect: (planId: string) => void;
}

export const PlanCard: React.FC<PlanCardProps> = ({
PlanCard.displayName = 'PlanCard';
  plan,
  billingCycle,
  isSelected = false,
  isPopular = false,
  onSelect,
}) => {
  const calculatePrice = (): string => {
    if (plan.price_cents === 0) return 'Free';
    
    let priceCents = plan.price_cents;
    
    if (billingCycle === 'yearly' && plan.billing_cycle === 'monthly' && plan.has_annual_discount) {
      const discountPercent = plan.annual_discount_percent ? parseFloat(plan.annual_discount_percent.toString()) : 0;
      priceCents = priceCents * 12 * (1 - discountPercent / 100);
    } else if (billingCycle === 'monthly' && plan.has_promotional_discount && plan.promotional_discount_percent && !plan.promotional_discount_code) {
      const discountPercent = parseFloat(plan.promotional_discount_percent.toString());
      priceCents = priceCents * (1 - discountPercent / 100);
    }
    
    const amount = priceCents / 100;
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: plan.currency || 'USD'
    }).format(amount);
  };

  const getOriginalPrice = (): string | null => {
    if (plan.price_cents === 0) return null;
    
    const hasDiscount = (billingCycle === 'yearly' && plan.has_annual_discount && plan.annual_discount_percent) ||
                        (plan.has_promotional_discount && plan.promotional_discount_percent && !plan.promotional_discount_code);
    
    if (!hasDiscount) return null;
    
    const originalPrice = billingCycle === 'yearly' 
      ? (plan.price_cents * 12) / 100
      : plan.price_cents / 100;
    
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: plan.currency || 'USD',
    }).format(originalPrice);
  };

  const getDiscountBadge = (): React.ReactElement | null => {
    const annualPercent = plan.annual_discount_percent ? parseFloat(plan.annual_discount_percent.toString()) : 0;
    const promotionalPercent = plan.promotional_discount_percent ? parseFloat(plan.promotional_discount_percent.toString()) : 0;
    
    // Prioritize annual discount when viewing yearly billing
    if (billingCycle === 'yearly' && plan.has_annual_discount && annualPercent > 0 && plan.billing_cycle === 'monthly') {
      return (
        <div className="absolute -top-2 -right-2 bg-emerald-500 text-white px-3 py-1 rounded-full text-xs font-semibold shadow-md">
          💰 Save {annualPercent}%
        </div>
      );
    }
    
    // Show promotional discount when not viewing yearly or no annual discount
    if (plan.has_promotional_discount && promotionalPercent > 0) {
      return (
        <div className="absolute -top-2 -right-2 bg-theme-error text-white px-3 py-1 rounded-full text-xs font-semibold shadow-md">
          🔥 {promotionalPercent}% OFF
        </div>
      );
    }
    
    return null;
  };

  const getAnnualBillingBadge = (): React.ReactElement | null => {
    const annualPercent = plan.annual_discount_percent ? parseFloat(plan.annual_discount_percent.toString()) : 0;
    
    // Show annual billing badge when viewing monthly billing but annual discount is available
    if (billingCycle === 'monthly' && plan.has_annual_discount && annualPercent > 0 && plan.billing_cycle === 'monthly' && plan.price_cents > 0) {
      return (
        <div className="absolute -top-2 -left-2 bg-gradient-to-r from-theme-interactive-primary to-theme-interactive-primary-hover text-white px-3 py-1 rounded-full text-xs font-semibold shadow-md">
          📅 {annualPercent}% off yearly
        </div>
      );
    }
    
    return null;
  };

  const getFeatures = (): string[] => {
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
        'Team collaboration'
      ];
    } else if (baseName.includes('enterprise') || baseName.includes('business')) {
      return [
        'Everything in Pro',
        'Advanced security',
        'Custom SLA',
        'Dedicated support',
        'On-premise option'
      ];
    }
    return [
      'Core features',
      'Standard support',
      'Basic analytics'
    ];
  };

  const originalPrice = getOriginalPrice();

  return (
    <div
      onClick={() => onSelect(plan.id)}
      className={`relative cursor-pointer transition-all duration-300 h-full ${
        isSelected ? 'scale-105' : 'hover:scale-102'
      }`}
    >
      {/* Card Container */}
      <div className={`relative rounded-xl border-2 p-6 transition-all duration-300 h-full flex flex-col ${
        isSelected
          ? 'border-theme-interactive-primary bg-theme-surface shadow-2xl shadow-theme-interactive-primary/20'
          : isPopular
          ? 'border-theme-interactive-primary hover:border-theme-interactive-primary-hover bg-theme-surface hover:shadow-lg hover:shadow-theme-interactive-primary/10'
          : 'border-theme hover:border-theme-focus bg-theme-surface hover:shadow-md'
      } ${isSelected ? 'ring-2 ring-theme-interactive-primary/30' : ''}`}>
        
        {/* Discount Badge */}
        {getDiscountBadge()}

        {/* Annual Billing Badge */}
        {getAnnualBillingBadge()}

        {/* Popular Badge */}
        {isPopular && (
          <div className="absolute -top-3 left-1/2 transform -translate-x-1/2">
            <div className="bg-theme-interactive-primary text-white px-3 py-1 rounded-full text-xs font-semibold flex items-center space-x-1">
              <StarSolidIcon className="h-3 w-3" />
              <span>Most Popular</span>
            </div>
          </div>
        )}

        {/* Selection Indicator */}
        {isSelected && (
          <div className="absolute top-4 right-4">
            <div className="w-6 h-6 bg-theme-interactive-primary rounded-full flex items-center justify-center">
              <CheckIcon className="h-4 w-4 text-white" />
            </div>
          </div>
        )}

        {/* Plan Header */}
        <div className="text-center mb-6 mt-2">
          <h3 className="text-xl font-bold text-theme-primary mb-2">
            {plan.name}
          </h3>
          {plan.description && (
            <p className="text-theme-secondary text-sm mb-4">{plan.description}</p>
          )}
          
          {/* Pricing */}
          <div className="mb-4">
            <div className="text-3xl font-bold text-theme-primary mb-1">
              {calculatePrice()}
            </div>
            {plan.price_cents > 0 && (
              <div className="text-sm text-theme-secondary">
                per {billingCycle === 'yearly' ? 'year' : 'month'}
              </div>
            )}
            
            {/* Original Price */}
            {originalPrice && (
              <div className="mt-1">
                <span className="text-sm text-theme-tertiary line-through">
                  {originalPrice}
                </span>
                <span className="ml-2 text-xs text-theme-success font-semibold">
                  {billingCycle === 'yearly' && plan.has_annual_discount
                    ? `${plan.annual_discount_percent}% saved`
                    : plan.has_promotional_discount && plan.promotional_discount_percent
                    ? `${plan.promotional_discount_percent}% off`
                    : ''}
                </span>
              </div>
            )}
            
            {billingCycle === 'yearly' && plan.price_cents > 0 && (
              <div className="text-xs text-theme-tertiary mt-1">
                {(() => {
                  // Calculate the monthly equivalent of the yearly discounted price
                  let monthlyEquivalent = plan.price_cents;
                  if (plan.has_annual_discount && plan.annual_discount_percent) {
                    const discountPercent = parseFloat(plan.annual_discount_percent.toString());
                    monthlyEquivalent = plan.price_cents * (1 - discountPercent / 100);
                  }
                  return new Intl.NumberFormat('en-US', {
                    style: 'currency',
                    currency: plan.currency || 'USD'
                  }).format(monthlyEquivalent / 100);
                })()}/month billed annually
              </div>
            )}
          </div>

          {/* Trial Badge */}
          {plan.trial_days > 0 && (
            <div className="inline-flex items-center space-x-1 bg-gradient-to-r from-emerald-500 to-green-500 text-white px-3 py-1.5 rounded-full text-xs font-bold shadow-md border border-emerald-400/20">
              <span>🎁</span>
              <span>{plan.trial_days} day free trial</span>
            </div>
          )}
        </div>

        {/* Features - flex-grow to push CTA to bottom */}
        <div className="flex-grow">
          <ul className="space-y-3 mb-6">
            {getFeatures().map((feature, index) => (
              <li key={index} className="flex items-start space-x-3">
                <CheckIcon className="h-4 w-4 text-theme-success flex-shrink-0 mt-0.5" />
                <span className="text-sm text-theme-secondary">{feature}</span>
              </li>
            ))}
          </ul>
        </div>

        {/* CTA Button - stays at bottom */}
        <div className="text-center mt-auto">
          {isSelected ? (
            <div className="w-full bg-theme-interactive-primary text-white py-3 px-4 rounded-lg font-semibold flex items-center justify-center space-x-2 shadow-lg">
              <CheckIcon className="h-4 w-4" />
              <span>Selected</span>
            </div>
          ) : (
            <div className={`w-full py-3 px-4 rounded-lg font-semibold transition-all ${
              isPopular
                ? 'bg-theme-interactive-primary text-white hover:bg-theme-interactive-primary-hover shadow-md hover:shadow-lg'
                : 'border-2 border-theme-interactive-primary text-theme-interactive-primary hover:bg-theme-interactive-primary hover:text-white hover:shadow-md'
            }`}>
              <span className="flex items-center justify-center space-x-2">
                <span>Choose {plan.name}</span>
                <ArrowRightIcon className="h-4 w-4" />
              </span>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};
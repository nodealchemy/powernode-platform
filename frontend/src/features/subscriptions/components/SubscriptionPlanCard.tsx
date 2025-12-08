
import { Plan } from '@/features/plans/services/plansApi';
import { Button } from '@/shared/components/ui/Button';

interface SubscriptionPlanCardProps {
  plan: Plan;
  isActive?: boolean;
  onSubscribe?: (planId: string) => void;
  onManage?: (planId: string) => void;
  loading?: boolean;
  billingCycle?: 'monthly' | 'yearly' | 'quarterly';
  isBestValue?: boolean;
  isPopular?: boolean;
  // Comparison functionality
  showComparison?: boolean;
  isSelectedForComparison?: boolean;
  onComparisonToggle?: (planId: string) => void;
}

interface PlanWithDiscounts {
  billing_cycle?: string;
  has_annual_discount?: boolean;
  annual_discount_percent?: number | string;
  has_promotional_discount?: boolean;
  promotional_discount_percent?: number | string;
  promotional_discount_code?: string;
}

const formatPrice = (price: {cents: number; currency_iso: string} | number | null | undefined, currency?: string, interval?: string, plan?: PlanWithDiscounts, billingCycle?: string) => {
  let priceCents: number;
  let actualCurrency = currency;
  
  if (price == null) {
    return 'Free';
  }
  
  if (typeof price === 'object' && 'cents' in price) {
    priceCents = price.cents;
    actualCurrency = actualCurrency || price.currency_iso;
  } else if (typeof price === 'number') {
    priceCents = price;
  } else {
    return 'Free';
  }
  
  if (priceCents === 0 || isNaN(priceCents)) {
    return 'Free';
  }
  
  // Apply discounts based on badge display logic (matches badge logic)
  if (plan && billingCycle === 'yearly' && plan.billing_cycle === 'monthly' && plan.has_annual_discount) {
    // When viewing yearly, apply annual discount
    const discountPercent = plan.annual_discount_percent ? parseFloat(plan.annual_discount_percent.toString()) : 0;
    if (interval === 'yearly' || interval === 'year') {
      priceCents = priceCents * 12 * (1 - discountPercent / 100);
    }
  } else if (plan && billingCycle === 'monthly' && plan.has_promotional_discount && plan.promotional_discount_percent && !plan.promotional_discount_code) {
    // When viewing monthly with promotional discount (only if no code required), apply promotional discount
    const discountPercent = parseFloat(plan.promotional_discount_percent.toString());
    priceCents = priceCents * (1 - discountPercent / 100);
  }
  
  const formattedPrice = new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: actualCurrency || 'USD',
  }).format(priceCents / 100);
  
  if (!interval) return formattedPrice;
  
  const intervalLabel = interval === 'yearly' ? 'year' : interval === 'quarterly' ? 'quarter' : 'month';
  return `${formattedPrice}/${intervalLabel}`;
};


const getFeatureList = (features: Record<string, boolean | string | number>, limits?: Record<string, number>) => {
  const featureList = [];
  
  if (limits) {
    if (limits.users) {
      featureList.push(`${limits.users === -1 ? 'Unlimited' : limits.users} users`);
    }
    if (limits.projects) {
      featureList.push(`${limits.projects === -1 ? 'Unlimited' : limits.projects} projects`);
    }
    if (limits.storage) {
      featureList.push(`${limits.storage}GB storage`);
    }
  }
  
  Object.entries(features).forEach(([key, value]) => {
    if (value === true) {
      featureList.push(key.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase()));
    }
  });
  
  return featureList;
};

export const SubscriptionPlanCard: React.FC<SubscriptionPlanCardProps> = ({
  plan,
  isActive = false,
  onSubscribe,
  onManage,
  loading = false,
  billingCycle = 'monthly',
  isBestValue = false,
  isPopular = false,
  showComparison = false,
  isSelectedForComparison = false,
  onComparisonToggle,
}) => {
  const featureList = getFeatureList(plan.features || {}, plan.limits || {});

  const getPlanDiscountBadge = (): React.ReactElement | null => {
    // When viewing yearly billing, prioritize annual discount badge
    if (billingCycle === 'yearly' && plan.has_annual_discount && plan.annual_discount_percent && plan.annual_discount_percent > 0) {
      const annualPercent = parseFloat(plan.annual_discount_percent.toString());
      return (
        <div className="absolute -top-3 -right-3 z-10">
          <div className="relative">
            <div className="bg-gradient-to-r from-green-500 to-emerald-600 text-white px-4 py-1.5 rounded-full text-xs font-bold shadow-lg transform hover:scale-105 transition-transform flex items-center gap-1">
              <span className="text-base">💰</span>
              <span>Save {annualPercent}%</span>
            </div>
            <div className="absolute inset-0 bg-gradient-to-r from-green-500 to-emerald-600 rounded-full blur-lg opacity-50 -z-10"></div>
          </div>
        </div>
      );
    }
    
    // Check for promotional discount (when not viewing yearly or no annual discount)
    if (plan.has_promotional_discount && plan.promotional_discount_percent && plan.promotional_discount_percent > 0) {
      // Check if promotional discount is currently active
      const now = new Date();
      const startDate = plan.promotional_discount_start ? new Date(plan.promotional_discount_start) : null;
      const endDate = plan.promotional_discount_end ? new Date(plan.promotional_discount_end) : null;
      
      const isActive = (!startDate || startDate <= now) && (!endDate || endDate >= now);
      
      if (isActive) {
        const isLimitedTime = endDate && endDate > now;
        const daysLeft = isLimitedTime ? Math.ceil((endDate.getTime() - now.getTime()) / (1000 * 60 * 60 * 24)) : null;
        
        return (
          <div className="absolute -top-3 -right-3 z-10">
            <div className="relative">
              <div className="bg-gradient-to-r from-red-500 to-pink-600 text-white px-4 py-1.5 rounded-full text-xs font-bold shadow-lg animate-pulse transform hover:scale-105 transition-transform flex items-center gap-1">
                <span className="text-base">🔥</span>
                <span>{plan.promotional_discount_percent}% OFF</span>
                {daysLeft && daysLeft <= 7 && (
                  <span className="text-[10px] opacity-90">({daysLeft}d left)</span>
                )}
              </div>
              <div className="absolute inset-0 bg-gradient-to-r from-red-500 to-pink-600 rounded-full blur-lg opacity-50 -z-10 animate-pulse"></div>
            </div>
          </div>
        );
      }
    }
    
    // Check for volume discount
    if (plan.has_volume_discount && plan.volume_discount_tiers && plan.volume_discount_tiers.length > 0) {
      const maxDiscount = Math.max(...plan.volume_discount_tiers.map(tier => tier.discount_percent));
      if (maxDiscount > 0) {
        return (
          <div className="absolute -top-3 -right-3 z-10">
            <div className="relative">
              <div className="bg-gradient-to-r from-purple-500 to-indigo-600 text-white px-4 py-1.5 rounded-full text-xs font-bold shadow-lg transform hover:scale-105 transition-transform flex items-center gap-1">
                <span className="text-base">📊</span>
                <span>Up to {maxDiscount}% off</span>
              </div>
              <div className="absolute inset-0 bg-gradient-to-r from-purple-500 to-indigo-600 rounded-full blur-lg opacity-50 -z-10"></div>
            </div>
          </div>
        );
      }
    }
    
    return null;
  };
  
  return (
    <div className={`relative border-2 rounded-lg p-6 overflow-visible transition-all h-[520px] flex flex-col ${
      isActive 
        ? 'border-theme-info bg-theme-info ring-2 ring-theme-info ring-opacity-20' 
        : isBestValue
        ? 'border-theme-success bg-gradient-to-br from-theme-surface to-theme-success bg-opacity-5 hover:shadow-xl'
        : isPopular
        ? 'border-theme-interactive-primary hover:shadow-xl'
        : 'border-theme card-theme hover:shadow-lg'
    }`}>
      {/* Discount Badge */}
      {getPlanDiscountBadge()}
      
      {/* Best Value / Popular Ribbon */}
      {(isBestValue || isPopular) && !isActive && (
        <div className="absolute -top-1 left-6">
          <div className={`${
            isBestValue 
              ? 'bg-gradient-to-r from-yellow-400 to-orange-500' 
              : 'bg-gradient-to-r from-blue-500 to-purple-600'
          } text-white px-3 py-1 text-[10px] font-bold uppercase tracking-wider rounded-b-md shadow-md`}>
            {isBestValue ? '✨ Best Value' : '⭐ Most Popular'}
          </div>
        </div>
      )}

      <div className="flex justify-between items-start mb-2 mt-2">
        <h4 className="text-lg font-semibold text-theme-primary">{plan.name}</h4>
        <div className="flex items-center space-x-2">
          {/* Plan Comparison Checkbox */}
          {showComparison && onComparisonToggle && (
            <div className="flex flex-col items-center">
              <label 
                htmlFor={`compare-subscription-${plan.id}`}
                className="flex flex-col items-center cursor-pointer group/compare hover:bg-theme-surface p-1.5 rounded transition-colors"
                title="Add to comparison"
              >
                <input
                  id={`compare-subscription-${plan.id}`}
                  type="checkbox"
                  checked={isSelectedForComparison}
                  onChange={() => onComparisonToggle(plan.id)}
                  className="w-3.5 h-3.5 text-theme-interactive-primary border-theme-border rounded focus:ring-theme-interactive-primary focus:ring-1 transition-colors"
                />
                <span className="text-xs text-theme-secondary mt-0.5 group-hover/compare:text-theme-primary transition-colors">
                  Compare
                </span>
              </label>
            </div>
          )}
          {isActive && (
            <span className="badge-theme badge-theme-info badge-theme-sm">
              Current Plan
            </span>
          )}
        </div>
      </div>
      
      <div className="mt-2">
        <p className="text-3xl font-bold text-theme-primary">
          {formatPrice((plan as any).price_cents || (plan as any).price, plan.currency, billingCycle === 'yearly' ? 'yearly' : (plan as any).billing_cycle || (plan as any).interval, plan as PlanWithDiscounts, billingCycle)}
        </p>
        {/* Show original price with strikethrough if discounted */}
        {((billingCycle === 'yearly' && plan.has_annual_discount && plan.annual_discount_percent) ||
          (plan.has_promotional_discount && plan.promotional_discount_percent && !plan.promotional_discount_code)) && (
          <p className="text-sm text-theme-tertiary line-through mt-1">
            {(() => {
              const priceCents = (plan as any).price_cents || (plan as any).price || 0;
              const originalPrice = billingCycle === 'yearly' 
                ? (priceCents * 12) / 100
                : priceCents / 100;
              return new Intl.NumberFormat('en-US', {
                style: 'currency',
                currency: plan.currency || 'USD',
              }).format(originalPrice);
            })()}
            <span className="ml-1 text-theme-success font-medium no-underline">
              {billingCycle === 'yearly' && plan.has_annual_discount
                ? `(${plan.annual_discount_percent}% saved)`
                : plan.has_promotional_discount && plan.promotional_discount_percent
                ? `(${plan.promotional_discount_percent}% off)`
                : ''}
            </span>
          </p>
        )}
      </div>
      
      {((plan as any).trial_days || (plan as any).trialDays) && ((plan as any).trial_days || (plan as any).trialDays) > 0 && !isActive && (
        <div className="flex items-center gap-2 mt-2">
          <span className="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-theme-success-background text-theme-success border border-theme-success-border">
            <span className="mr-1">🎁</span>
            {(plan as any).trial_days || (plan as any).trialDays}-day free trial
          </span>
        </div>
      )}
      
      <div className="mt-4">
        <ul className="space-y-2 text-sm text-theme-secondary">
          {featureList.slice(0, 4).map((feature, index) => (
            <li key={index} className="flex items-center">
              <svg className="w-4 h-4 text-theme-success mr-2" fill="currentColor" viewBox="0 0 20 20">
                <path fillRule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clipRule="evenodd" />
              </svg>
              {feature}
            </li>
          ))}
          {featureList.length > 4 && (
            <li className="text-xs text-theme-tertiary">
              +{featureList.length - 4} more features
            </li>
          )}
        </ul>
      </div>
      
      <div className="mt-auto pt-6">
        {isActive ? (
          <Button
            onClick={() => onManage?.(plan.id)}
            disabled={loading}
            loading={loading}
            variant="secondary"
            fullWidth
          >
            {loading ? 'Loading...' : 'Manage Plan'}
          </Button>
        ) : (
          <Button
            onClick={() => onSubscribe?.(plan.id)}
            disabled={loading}
            loading={loading}
            variant="primary"
            fullWidth
          >
            {loading ? 'Loading...' : 'Subscribe'}
          </Button>
        )}
      </div>
      
      {plan.status !== 'active' && (
        <p className="text-xs text-theme-tertiary mt-2 text-center">
          Plan currently {plan.status}
        </p>
      )}
    </div>
  );
};
import React from 'react';
import { Plan, Subscription } from '../services/subscriptionService';
import { Check, Star, TrendingUp, TrendingDown } from 'lucide-react';

interface SimplePlanBrowserProps {
  plans: Plan[];
  currentSubscription?: Subscription | null;
  onPlanSelect: (planId: string) => void;
  loading?: boolean;
  billingCycle: 'monthly' | 'yearly';
  onBillingCycleChange: (cycle: 'monthly' | 'yearly') => void;
  className?: string;
}

export const SimplePlanBrowser: React.FC<SimplePlanBrowserProps> = ({
  plans,
  currentSubscription,
  onPlanSelect,
  loading = false,
  billingCycle,
  onBillingCycleChange,
  className = ''
}) => {
  const formatPrice = (priceCents: number, cycle: string) => {
    if (priceCents === 0) return 'Free';
    
    const price = (priceCents / 100).toFixed(2);
    const cycleText = cycle === 'monthly' ? 'month' : 'year';
    return `$${price}/${cycleText}`;
  };

  const getPlanPriceCents = (plan: Plan) => {
    if (typeof plan.price === 'number') {
      return plan.price;
    }
    return plan.price.cents || 0;
  };

  const getYearlyPrice = (plan: Plan) => {
    const priceCents = getPlanPriceCents(plan);
    // For now, assume 10% yearly discount - this would come from plan data in real app
    const discountMultiplier = 0.9; // 10% discount
    return Math.round(priceCents * 12 * discountMultiplier);
  };

  const getDisplayPrice = (plan: Plan) => {
    if (billingCycle === 'yearly') {
      return getYearlyPrice(plan);
    }
    return getPlanPriceCents(plan);
  };

  const getSavingsPercent = (plan: Plan) => {
    if (billingCycle === 'yearly') {
      return 10; // 10% savings for yearly billing
    }
    return 0;
  };

  const getPlanComparison = (plan: Plan) => {
    if (!currentSubscription) return null;
    
    const currentPlanPrice = getPlanPriceCents(currentSubscription.plan);
    const planPrice = getPlanPriceCents(plan);
    
    if (plan.id === currentSubscription.plan.id) {
      return 'current';
    }
    
    if (planPrice > currentPlanPrice) {
      return 'upgrade';
    }
    
    if (planPrice < currentPlanPrice) {
      return 'downgrade';
    }
    
    return 'same';
  };

  const getActionButtonText = (plan: Plan) => {
    const comparison = getPlanComparison(plan);
    
    switch (comparison) {
      case 'current':
        return 'Current Plan';
      case 'upgrade':
        return 'Upgrade';
      case 'downgrade':
        return 'Downgrade';
      default:
        return 'Select Plan';
    }
  };

  const getActionButtonVariant = (plan: Plan) => {
    const comparison = getPlanComparison(plan);
    
    switch (comparison) {
      case 'current':
        return 'secondary';
      case 'upgrade':
        return 'primary';
      default:
        return 'secondary';
    }
  };

  const isCurrentPlan = (plan: Plan) => {
    return currentSubscription?.plan.id === plan.id;
  };

  const getKeyFeatures = (plan: Plan) => {
    if (plan.features && typeof plan.features === 'object') {
      return Object.entries(plan.features)
        .filter(([_, value]) => value === true || (typeof value === 'string' && value.length > 0))
        .slice(0, 3)
        .map(([key, value]) => {
          if (typeof value === 'boolean') {
            return key.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase());
          }
          return `${key.replace(/_/g, ' ')}: ${value}`;
        });
    }
    return [];
  };

  if (loading) {
    return (
      <div className={`space-y-4 ${className}`}>
        <div className="flex justify-center">
          <div className="animate-pulse flex space-x-2 bg-theme-surface rounded-lg p-1">
            <div className="h-8 w-16 bg-theme-secondary rounded"></div>
            <div className="h-8 w-16 bg-theme-secondary rounded"></div>
          </div>
        </div>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {[1, 2, 3].map((i) => (
            <div key={i} className="card-theme p-4 animate-pulse">
              <div className="h-6 bg-theme-secondary rounded mb-2"></div>
              <div className="h-8 bg-theme-secondary rounded mb-4"></div>
              <div className="space-y-2 mb-4">
                <div className="h-4 bg-theme-secondary rounded"></div>
                <div className="h-4 bg-theme-secondary rounded w-3/4"></div>
              </div>
              <div className="h-10 bg-theme-secondary rounded"></div>
            </div>
          ))}
        </div>
      </div>
    );
  }

  const publicPlans = plans.filter(plan => plan.isPublic);

  return (
    <div className={`space-y-6 ${className}`}>
      {/* Billing Cycle Toggle */}
      <div className="flex justify-center">
        <div className="flex bg-theme-surface rounded-lg p-1 shadow-sm border border-theme">
          <button
            onClick={() => onBillingCycleChange('monthly')}
            className={`px-4 py-2 rounded-md text-sm font-medium transition-colors ${
              billingCycle === 'monthly'
                ? 'bg-theme-primary text-white shadow-sm'
                : 'text-theme-secondary hover:text-theme-primary'
            }`}
          >
            Monthly
          </button>
          <button
            onClick={() => onBillingCycleChange('yearly')}
            className={`px-4 py-2 rounded-md text-sm font-medium transition-colors relative ${
              billingCycle === 'yearly'
                ? 'bg-theme-primary text-white shadow-sm'
                : 'text-theme-secondary hover:text-theme-primary'
            }`}
          >
            Yearly
            <span className="ml-1 text-xs bg-theme-success text-white px-1.5 py-0.5 rounded">
              Save up to 20%
            </span>
          </button>
        </div>
      </div>

      {/* Plans Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {publicPlans.map((plan) => {
          const comparison = getPlanComparison(plan);
          const savingsPercent = getSavingsPercent(plan);
          const keyFeatures = getKeyFeatures(plan);
          const displayPrice = getDisplayPrice(plan);
          
          return (
            <div
              key={plan.id}
              className={`card-theme relative p-6 transition-all duration-200 hover:shadow-lg ${
                isCurrentPlan(plan) 
                  ? 'ring-2 ring-theme-primary border-theme-primary' 
                  : 'border-theme hover:border-theme-primary'
              }`}
            >
              {/* Current Plan Badge */}
              {isCurrentPlan(plan) && (
                <div className="absolute -top-3 left-1/2 transform -translate-x-1/2">
                  <div className="bg-theme-primary text-white px-3 py-1 rounded-full text-xs font-medium flex items-center space-x-1">
                    <Check className="h-3 w-3" />
                    <span>Current Plan</span>
                  </div>
                </div>
              )}

              {/* Upgrade/Downgrade Badge */}
              {comparison === 'upgrade' && (
                <div className="absolute -top-3 right-4">
                  <div className="bg-theme-success text-white px-2 py-1 rounded-full text-xs font-medium flex items-center space-x-1">
                    <TrendingUp className="h-3 w-3" />
                    <span>Upgrade</span>
                  </div>
                </div>
              )}

              {comparison === 'downgrade' && (
                <div className="absolute -top-3 right-4">
                  <div className="bg-theme-secondary text-white px-2 py-1 rounded-full text-xs font-medium flex items-center space-x-1">
                    <TrendingDown className="h-3 w-3" />
                    <span>Downgrade</span>
                  </div>
                </div>
              )}

              {/* Popular Badge */}
              {plan.name.toLowerCase().includes('pro') && !isCurrentPlan(plan) && (
                <div className="absolute -top-3 left-4">
                  <div className="bg-theme-warning text-white px-2 py-1 rounded-full text-xs font-medium flex items-center space-x-1">
                    <Star className="h-3 w-3" />
                    <span>Popular</span>
                  </div>
                </div>
              )}

              {/* Plan Header */}
              <div className="text-center mb-4">
                <h3 className="text-lg font-semibold text-theme-primary mb-2">
                  {plan.name}
                </h3>
                <div className="space-y-1">
                  <p className="text-3xl font-bold text-theme-primary">
                    {formatPrice(displayPrice, billingCycle)}
                  </p>
                  {savingsPercent > 0 && (
                    <p className="text-sm text-theme-success font-medium">
                      Save {savingsPercent}% with yearly billing
                    </p>
                  )}
                </div>
              </div>

              {/* Plan Description - removed as not in Plan interface */}

              {/* Key Features */}
              {keyFeatures.length > 0 && (
                <div className="space-y-2 mb-6">
                  {keyFeatures.map((feature, index) => (
                    <div key={index} className="flex items-center text-sm text-theme-secondary">
                      <Check className="h-4 w-4 text-theme-success mr-2 flex-shrink-0" />
                      <span>{feature}</span>
                    </div>
                  ))}
                </div>
              )}

              {/* Action Button */}
              <button
                onClick={() => onPlanSelect(plan.id)}
                disabled={isCurrentPlan(plan)}
                className={`w-full btn-theme ${
                  getActionButtonVariant(plan) === 'primary' 
                    ? 'btn-theme-primary' 
                    : 'btn-theme-secondary'
                } ${
                  isCurrentPlan(plan) 
                    ? 'opacity-50 cursor-not-allowed' 
                    : 'hover:scale-105 transform transition-transform'
                }`}
              >
                {getActionButtonText(plan)}
              </button>

              {/* Trial Information */}
              {plan.trialDays && plan.trialDays > 0 && !isCurrentPlan(plan) && (
                <p className="text-xs text-theme-secondary text-center mt-2">
                  {plan.trialDays}-day free trial included
                </p>
              )}
            </div>
          );
        })}
      </div>

      {publicPlans.length === 0 && (
        <div className="text-center py-8">
          <p className="text-theme-secondary">No plans available at this time.</p>
        </div>
      )}
    </div>
  );
};
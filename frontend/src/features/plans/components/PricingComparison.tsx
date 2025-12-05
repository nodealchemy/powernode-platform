
import { Plan } from '../services/plansApi';
import { CheckIcon, XMarkIcon } from '@heroicons/react/24/outline';

interface PricingComparisonProps {
  plans: Plan[];
  billingCycle: 'monthly' | 'yearly';
  selectedPlanId?: string | null;
  onSelectPlan?: (planId: string) => void;
}

export const PricingComparison: React.FC<PricingComparisonProps> = ({
  plans,
  billingCycle,
  selectedPlanId,
  onSelectPlan
}) => {
  const calculatePrice = (plan: Plan): { price: number; originalPrice?: number; savings?: number } => {
    if (plan.price_cents === 0) {
      return { price: 0 };
    }

    const monthlyPrice = plan.price_cents / 100;

    if (billingCycle === 'yearly') {
      const yearlyPrice = monthlyPrice * 12;
      
      if (plan.has_annual_discount && plan.annual_discount_percent) {
        const discount = yearlyPrice * (plan.annual_discount_percent / 100);
        return {
          price: yearlyPrice - discount,
          originalPrice: yearlyPrice,
          savings: discount
        };
      }
      
      return { price: yearlyPrice };
    }

    // Monthly pricing with promotional discount if applicable
    if (plan.has_promotional_discount && plan.promotional_discount_percent && !plan.promotional_discount_code) {
      const discount = monthlyPrice * (plan.promotional_discount_percent / 100);
      return {
        price: monthlyPrice - discount,
        originalPrice: monthlyPrice,
        savings: discount
      };
    }

    return { price: monthlyPrice };
  };

  const formatCurrency = (amount: number, currency = 'USD') => {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency,
      minimumFractionDigits: 0,
      maximumFractionDigits: amount < 100 ? 2 : 0
    }).format(amount);
  };

  const getAnnualSavingsPercentage = (plan: Plan): number | null => {
    if (billingCycle === 'yearly' && plan.has_annual_discount && plan.annual_discount_percent) {
      return plan.annual_discount_percent;
    }
    return null;
  };

  return (
    <div className="overflow-x-auto">
      <table className="w-full">
        <thead className="bg-theme-surface border-b-2 border-theme">
          <tr>
            <th className="px-6 py-4 text-left text-sm font-semibold text-theme-primary">
              Plan Features
            </th>
            {plans.map(plan => {
              const pricing = calculatePrice(plan);
              const savingsPercent = getAnnualSavingsPercentage(plan);
              const isSelected = plan.id === selectedPlanId;
              
              return (
                <th key={plan.id} className="px-6 py-4 text-center min-w-[180px]">
                  <div className={`space-y-2 ${isSelected ? 'ring-2 ring-theme-interactive-primary rounded-lg p-3 -m-3' : ''}`}>
                    <div className="font-bold text-lg text-theme-primary">{plan.name}</div>
                    
                    {/* Price Display */}
                    <div className="space-y-1">
                      {pricing.originalPrice && (
                        <div className="text-sm text-theme-tertiary line-through">
                          {formatCurrency(pricing.originalPrice, plan.currency)}
                        </div>
                      )}
                      <div className="text-2xl font-bold text-theme-primary">
                        {pricing.price === 0 ? 'Free' : formatCurrency(pricing.price, plan.currency)}
                      </div>
                      <div className="text-xs text-theme-secondary">
                        per {billingCycle === 'yearly' ? 'year' : 'month'}
                      </div>
                    </div>

                    {/* Savings Badge */}
                    {savingsPercent && (
                      <div className="inline-flex items-center px-2 py-1 rounded-full bg-theme-success-background text-theme-success text-xs font-bold">
                        <span className="mr-1">💰</span>
                        Save {savingsPercent}%
                      </div>
                    )}

                    {/* Annual Savings Amount */}
                    {pricing.savings && billingCycle === 'yearly' && (
                      <div className="text-xs text-theme-success font-medium">
                        You save {formatCurrency(pricing.savings, plan.currency)}/year
                      </div>
                    )}

                    {/* Trial Badge */}
                    {plan.trial_days > 0 && (
                      <div className="text-xs text-theme-info">
                        🎁 {plan.trial_days}-day free trial
                      </div>
                    )}

                    {/* Select Button */}
                    {onSelectPlan && (
                      <button
                        onClick={() => onSelectPlan(plan.id)}
                        className={`w-full px-4 py-2 rounded-lg font-medium transition-colors ${
                          isSelected
                            ? 'bg-theme-interactive-primary text-white'
                            : 'bg-theme-surface hover:bg-theme-surface-hover border border-theme text-theme-primary'
                        }`}
                      >
                        {isSelected ? 'Selected' : 'Select Plan'}
                      </button>
                    )}
                  </div>
                </th>
              );
            })}
          </tr>
        </thead>
        <tbody className="divide-y divide-theme">
          {/* User Limits */}
          <tr className="hover:bg-theme-surface-hover">
            <td className="px-6 py-4 text-sm font-medium text-theme-primary">Users</td>
            {plans.map(plan => (
              <td key={plan.id} className="px-6 py-4 text-center text-sm text-theme-secondary">
                {plan.limits?.users === -1 ? 'Unlimited' : plan.limits?.users || '—'}
              </td>
            ))}
          </tr>

          {/* Project Limits */}
          <tr className="hover:bg-theme-surface-hover">
            <td className="px-6 py-4 text-sm font-medium text-theme-primary">Projects</td>
            {plans.map(plan => (
              <td key={plan.id} className="px-6 py-4 text-center text-sm text-theme-secondary">
                {plan.limits?.projects === -1 ? 'Unlimited' : plan.limits?.projects || '—'}
              </td>
            ))}
          </tr>

          {/* Storage Limits */}
          <tr className="hover:bg-theme-surface-hover">
            <td className="px-6 py-4 text-sm font-medium text-theme-primary">Storage</td>
            {plans.map(plan => (
              <td key={plan.id} className="px-6 py-4 text-center text-sm text-theme-secondary">
                {plan.limits?.storage === -1 ? 'Unlimited' : `${plan.limits?.storage || 0} GB`}
              </td>
            ))}
          </tr>

          {/* Features */}
          <tr className="hover:bg-theme-surface-hover">
            <td className="px-6 py-4 text-sm font-medium text-theme-primary">API Access</td>
            {plans.map(plan => (
              <td key={plan.id} className="px-6 py-4 text-center">
                {plan.features?.api_access ? (
                  <CheckIcon className="w-5 h-5 text-theme-success mx-auto" />
                ) : (
                  <XMarkIcon className="w-5 h-5 text-theme-tertiary mx-auto" />
                )}
              </td>
            ))}
          </tr>

          <tr className="hover:bg-theme-surface-hover">
            <td className="px-6 py-4 text-sm font-medium text-theme-primary">Analytics</td>
            {plans.map(plan => (
              <td key={plan.id} className="px-6 py-4 text-center">
                {plan.features?.advanced_analytics ? (
                  <span className="text-sm text-theme-success">Advanced</span>
                ) : plan.features?.basic_analytics ? (
                  <span className="text-sm text-theme-secondary">Basic</span>
                ) : (
                  <XMarkIcon className="w-5 h-5 text-theme-tertiary mx-auto" />
                )}
              </td>
            ))}
          </tr>

          <tr className="hover:bg-theme-surface-hover">
            <td className="px-6 py-4 text-sm font-medium text-theme-primary">Support</td>
            {plans.map(plan => (
              <td key={plan.id} className="px-6 py-4 text-center text-sm text-theme-secondary">
                {plan.features?.dedicated_support ? 'Dedicated' :
                 plan.features?.priority_support ? 'Priority' :
                 plan.features?.basic_support ? 'Email' : '—'}
              </td>
            ))}
          </tr>

          {/* Annual Billing Comparison Row */}
          {billingCycle === 'monthly' && plans.some(p => p.has_annual_discount) && (
            <tr className="bg-theme-success-background">
              <td className="px-6 py-4 text-sm font-bold text-theme-success">
                💰 Annual Billing Savings
              </td>
              {plans.map(plan => {
                const monthlyTotal = (plan.price_cents / 100) * 12;
                const yearlyTotal = plan.has_annual_discount && plan.annual_discount_percent
                  ? monthlyTotal * (1 - plan.annual_discount_percent / 100)
                  : monthlyTotal;
                const savings = monthlyTotal - yearlyTotal;
                
                return (
                  <td key={plan.id} className="px-6 py-4 text-center">
                    {savings > 0 ? (
                      <div className="space-y-1">
                        <div className="text-lg font-bold text-theme-success">
                          {formatCurrency(savings, plan.currency)}
                        </div>
                        <div className="text-xs text-theme-success opacity-80">
                          per year ({plan.annual_discount_percent}% off)
                        </div>
                      </div>
                    ) : (
                      <span className="text-sm text-theme-tertiary">—</span>
                    )}
                  </td>
                );
              })}
            </tr>
          )}
        </tbody>
      </table>
    </div>
  );
};
import React from 'react';
import { Plan } from '../services/plansApi';

interface AnnualSavingsCalculatorProps {
  plan: Plan;
  className?: string;
}

export const AnnualSavingsCalculator: React.FC<AnnualSavingsCalculatorProps> = ({ 
  plan, 
  className = '' 
}) => {
  // Calculate annual savings if applicable
  const calculateAnnualSavings = () => {
    if (!plan.has_annual_discount || !plan.annual_discount_percent || plan.price_cents === 0) {
      return null;
    }

    const monthlyPrice = plan.price_cents / 100;
    const yearlyPriceWithoutDiscount = monthlyPrice * 12;
    const discountAmount = yearlyPriceWithoutDiscount * (plan.annual_discount_percent / 100);
    const yearlyPriceWithDiscount = yearlyPriceWithoutDiscount - discountAmount;

    return {
      monthlyPrice,
      yearlyPriceWithoutDiscount,
      yearlyPriceWithDiscount,
      totalSavings: discountAmount,
      percentSavings: plan.annual_discount_percent,
      effectiveMonthlyPrice: yearlyPriceWithDiscount / 12
    };
  };

  const savings = calculateAnnualSavings();

  if (!savings) {
    return null;
  }

  const formatCurrency = (amount: number) => {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: plan.currency || 'USD',
    }).format(amount);
  };

  return (
    <div className={`bg-theme-success-background border border-theme-success-border rounded-lg p-4 ${className}`}>
      <div className="flex items-start space-x-3">
        <div className="flex-shrink-0">
          <span className="text-2xl">💰</span>
        </div>
        <div className="flex-1 space-y-2">
          <h4 className="font-semibold text-theme-success">
            Save {savings.percentSavings}% with Annual Billing
          </h4>
          
          <div className="grid grid-cols-2 gap-4 text-sm">
            <div>
              <p className="text-theme-secondary">Monthly billing:</p>
              <p className="font-semibold text-theme-primary">
                {formatCurrency(savings.monthlyPrice)}/month
              </p>
              <p className="text-xs text-theme-tertiary">
                {formatCurrency(savings.yearlyPriceWithoutDiscount)}/year
              </p>
            </div>
            
            <div>
              <p className="text-theme-secondary">Annual billing:</p>
              <p className="font-semibold text-theme-primary">
                {formatCurrency(savings.effectiveMonthlyPrice)}/month
              </p>
              <p className="text-xs text-theme-tertiary">
                {formatCurrency(savings.yearlyPriceWithDiscount)}/year
              </p>
            </div>
          </div>
          
          <div className="pt-2 border-t border-theme-success-border">
            <p className="text-sm font-bold text-theme-success">
              You save {formatCurrency(savings.totalSavings)} per year!
            </p>
            <p className="text-xs text-theme-success opacity-80 mt-1">
              That's like getting {Math.round(savings.percentSavings * 12 / 100)} months free
            </p>
          </div>
        </div>
      </div>
    </div>
  );
};

export default AnnualSavingsCalculator;
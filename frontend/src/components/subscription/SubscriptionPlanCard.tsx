import React from 'react';
import { Plan } from '../../services/subscriptionService';

interface SubscriptionPlanCardProps {
  plan: Plan;
  isActive?: boolean;
  onSubscribe?: (planId: string) => void;
  onManage?: (planId: string) => void;
  loading?: boolean;
}

const formatPrice = (price: {cents: number; currency_iso: string} | number | null | undefined, currency?: string, interval?: string) => {
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
  
  const formattedPrice = new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: actualCurrency || 'USD',
  }).format(priceCents / 100);
  
  if (!interval) return formattedPrice;
  
  const intervalLabel = interval === 'yearly' ? 'year' : interval === 'quarterly' ? 'quarter' : 'month';
  return `${formattedPrice}/${intervalLabel}`;
};

const getFeatureList = (features: Record<string, any>, limits?: Record<string, any>) => {
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
}) => {
  const featureList = getFeatureList(plan.features, plan.limits);
  
  return (
    <div className={`border rounded-lg p-6 ${isActive ? 'border-theme-info bg-theme-info' : 'border-theme card-theme'}`}>
      <div className="flex justify-between items-start mb-2">
        <h4 className="text-lg font-semibold text-theme-primary">{plan.name}</h4>
        {isActive && (
          <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
            Current Plan
          </span>
        )}
      </div>
      
      <p className="text-3xl font-bold text-theme-primary mt-2">
        {formatPrice(plan.price, plan.currency, plan.billing_cycle || plan.interval)}
      </p>
      
      {plan.trialDays && plan.trialDays > 0 && !isActive && (
        <p className="text-sm text-green-600 mt-1">{plan.trialDays}-day free trial</p>
      )}
      
      <div className="mt-4">
        <ul className="space-y-2 text-sm text-theme-secondary">
          {featureList.slice(0, 4).map((feature, index) => (
            <li key={index} className="flex items-center">
              <svg className="w-4 h-4 text-green-500 mr-2" fill="currentColor" viewBox="0 0 20 20">
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
      
      <div className="mt-6">
        {isActive ? (
          <button
            onClick={() => onManage?.(plan.id)}
            disabled={loading}
            className="btn-theme btn-theme-secondary w-full py-2 px-4 disabled:opacity-50"
          >
            {loading ? 'Loading...' : 'Manage Plan'}
          </button>
        ) : (
          <button
            onClick={() => onSubscribe?.(plan.id)}
            disabled={loading}
            className="btn-theme btn-theme-primary w-full py-2 px-4 disabled:opacity-50"
          >
            {loading ? 'Loading...' : 'Subscribe'}
          </button>
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
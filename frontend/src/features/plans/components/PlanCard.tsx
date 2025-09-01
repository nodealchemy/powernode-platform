import React, { useState } from 'react';
import { CheckIcon, ChevronDownIcon, ChevronUpIcon } from '@heroicons/react/24/outline';
import { Link } from 'react-router-dom';
import { Plan } from '../services/plansApi';

interface PlanCardProps {
  plan: Plan;
  billingPeriod?: 'monthly' | 'annually';
  index?: number;
  featured?: boolean;
  className?: string;
  onSelect?: (plan: Plan) => void;
  isSelected?: boolean;
  isCurrentPlan?: boolean;
  disabled?: boolean;
  loading?: boolean;
  upgradeContext?: 'upgrade' | 'downgrade';
  customAction?: React.ReactNode;
  onBillingPeriodChange?: (period: 'monthly' | 'annually') => void;
}

export const PlanCard: React.FC<PlanCardProps> = ({
  plan,
  billingPeriod = 'monthly',
  index = 0,
  featured = false,
  className = '',
  onSelect,
  isSelected = false,
  isCurrentPlan = false,
  disabled = false,
  loading = false,
  upgradeContext,
  customAction,
  onBillingPeriodChange
}) => {
  const [showAllFeatures, setShowAllFeatures] = useState(false);
  const getPrice = () => {
    if (!plan.price_cents) return 0;
    const basePrice = plan.price_cents / 100;
    
    // Always show monthly equivalent for consistent display
    if (plan.billing_cycle === 'yearly') {
      return basePrice / 12; // Convert yearly price to monthly
    }
    
    if (plan.billing_cycle === 'quarterly') {
      return basePrice / 3; // Convert quarterly price to monthly
    }
    
    return basePrice;
  };

  const getPeriodText = () => {
    return 'month'; // Always show as monthly for consistency
  };

  const getFeaturesList = () => {
    
    if (plan.features && typeof plan.features === 'object' && Object.keys(plan.features).length > 0) {
      // Feature display mapping for better readability
      const featureLabels: { [key: string]: string } = {
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

      const enabledFeatures = Object.entries(plan.features)
        .filter(([key, enabled]) => enabled === true && !key.startsWith('max_') && !key.endsWith('_gb'))
        .map(([feature, _]) => featureLabels[feature] || feature.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase()))
        .sort();
      
      return enabledFeatures;
    }
    
    // Fallback if no features in plan data
    return ['Dashboard Access', 'Basic Features', 'Email Support'];
  };

  const getLimitsDisplay = () => {
    
    // Check if plan features contain limit information
    if (plan.features && typeof plan.features === 'object') {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const features = plan.features as any;
      
      const users = features.max_users === 9999 ? 'Unlimited' : `${features.max_users || 2}`;
      const storage = features.storage_gb === 10000 ? 'Unlimited' : 
                     features.storage_gb >= 1000 ? `${Math.floor(features.storage_gb / 1000)}TB` :
                     `${features.storage_gb || 1}GB`;
      
      // Calculate API requests display based on plan tier
      let apiRequests = '1k';
      if (features.api_access) {
        if (features.advanced_analytics && features.custom_integrations) {
          apiRequests = 'Unlimited';
        } else if (features.advanced_analytics) {
          apiRequests = '100k';
        } else {
          apiRequests = '10k';
        }
      }
      
      return { users, storage, apiRequests };
    }
    
    // Fallback limits if no plan data
    return {
      users: '2',
      storage: '1GB', 
      apiRequests: '1k'
    };
  };

  const displayPrice = getPrice();
  const features = getFeaturesList();
  const limits = getLimitsDisplay();

  const handleCardClick = () => {
    if (onSelect && !disabled && !loading) {
      onSelect(plan);
    }
  };

  const handleBillingToggle = (e: React.MouseEvent) => {
    e.stopPropagation(); // Prevent card selection
    if (onBillingPeriodChange) {
      const newPeriod = billingPeriod === 'monthly' ? 'annually' : 'monthly';
      onBillingPeriodChange(newPeriod);
    }
  };

  return (
    <div 
      className={`
        group relative flex flex-col w-full max-w-lg mx-auto cursor-pointer
        rounded-3xl p-8 transition-all duration-500 transform-gpu
        min-h-[680px] bg-theme-surface overflow-visible
        ${
          isSelected
            ? 'ring-4 ring-blue-500 ring-offset-4 ring-offset-blue-100/50 scale-110 shadow-2xl z-20 hover:scale-110 border-2 border-blue-400'
            : featured 
              ? 'ring-1 ring-blue-200 ring-offset-1 shadow-2xl scale-100 hover:scale-105 hover:shadow-xl border-primary'
              : 'border border-gray-200 hover:scale-105 scale-100 shadow-lg hover:shadow-xl hover:border-gray-300'
        }
        ${className}
      `}
      onClick={handleCardClick}
      style={{ 
        animationDelay: `${(index + 1) * 0.1}s`,
        transformOrigin: 'center center'
      }}
    >
      {/* Pure Background Gradient Layer */}
      <div 
        className={`
          absolute inset-0 rounded-3xl -z-10 transition-opacity duration-500
          ${
            isSelected
              ? 'bg-gradient-to-br from-blue-100 via-blue-50/60 to-indigo-100/60 opacity-100'
              : featured 
                ? 'bg-gradient-to-br from-blue-50/60 via-white to-purple-50/30 opacity-90'
                : 'bg-gradient-to-br from-gray-50/80 via-white to-slate-50/60 opacity-70'
          }
        `}
      />
      
      {/* Subtle Decorative Elements */}
      <div className="absolute top-0 right-0 w-24 h-24 bg-gradient-to-br from-blue-100/25 to-transparent rounded-full -mr-12 -mt-12 transition-transform duration-700 group-hover:scale-110" />
      <div className="absolute bottom-0 left-0 w-20 h-20 bg-gradient-to-tr from-indigo-100/20 to-transparent rounded-full -ml-10 -mb-10 transition-transform duration-700 group-hover:scale-110" />
      
      {/* Selected Plan Glow Effect */}
      {isSelected && (
        <div className="absolute inset-0 rounded-3xl -z-20">
          <div className="absolute inset-0 bg-gradient-to-r from-blue-400 via-blue-500 to-indigo-500 rounded-3xl blur-lg opacity-30 animate-pulse"></div>
          <div className="absolute inset-2 bg-gradient-to-r from-blue-300 via-blue-400 to-indigo-400 rounded-3xl blur-md opacity-20 animate-pulse"></div>
        </div>
      )}
      
      {/* Top Badges - Primary Row */}
      <div className="absolute -top-4 left-1/2 transform -translate-x-1/2 z-30 flex items-center justify-center gap-2 max-w-full px-2">
        {/* Popular Badge - Most prominent */}
        {featured && (
          <div className="relative">
            <div className="absolute inset-0 bg-gradient-to-r from-blue-600 to-indigo-600 rounded-full blur-sm opacity-60"></div>
            <span className="relative bg-gradient-to-r from-blue-600 to-indigo-600 text-white px-4 py-2 rounded-full text-sm font-bold shadow-xl border border-blue-400/30 whitespace-nowrap">
              <span className="mr-2">⭐</span>Most Popular
            </span>
          </div>
        )}
        
        {/* Free Plan Badge */}
        {displayPrice === 0 && (
          <span className="bg-gradient-to-r from-green-500 to-emerald-500 text-white px-3 py-1.5 rounded-full text-xs font-bold shadow-lg border border-green-400/30 whitespace-nowrap">
            <span className="mr-1">🎯</span>Free
          </span>
        )}
        
        
        {/* Best Value Badge for annual billing with discount */}
        {billingPeriod === 'annually' && plan.has_annual_discount && plan.annual_discount_percent && plan.annual_discount_percent >= 20 && (
          <span className="bg-gradient-to-r from-orange-500 to-red-500 text-white px-3 py-1.5 rounded-full text-xs font-bold shadow-lg border border-orange-400/30 whitespace-nowrap">
            <span className="mr-1">💰</span>Best Value
          </span>
        )}
      </div>


      {/* Header */}
      <div className="text-center mb-4 mt-4">
        <h3 
          className="text-2xl font-black mb-2 tracking-tight"
          style={{
            color: isSelected ? '#1e40af' : '#111827',
            fontWeight: '900',
            opacity: '1'
          }}
        >
          {plan.name}
        </h3>
        
        <p 
          className="text-sm line-clamp-2 mb-1 leading-none max-w-sm mx-auto"
          style={{
            color: isSelected ? '#374151' : '#6b7280',
            fontWeight: '500',
            opacity: '1',
            lineHeight: '1.1'
          }}
        >
          {plan.description || 'Professional subscription plan with comprehensive features'}
        </p>

        {/* Price Display */}
        <div className="mb-4">
          <div className="flex items-baseline justify-center mb-1">
            <span 
              className="text-4xl font-black tracking-tight"
              style={{
                color: isSelected 
                  ? '#1e40af' 
                  : displayPrice === 0 
                    ? '#059669' 
                    : '#111827',
                fontWeight: '900',
                opacity: '1'
              }}
            >
              {displayPrice === 0 ? 'Free' : 
               plan.currency === 'EUR' ? `€${displayPrice.toFixed(2)}` :
               `$${Math.floor(displayPrice)}`}
            </span>
            {displayPrice > 0 && (
              <button 
                className="ml-2 text-lg font-semibold self-end pb-1 hover:underline cursor-pointer transition-all duration-200 hover:opacity-80"
                style={{
                  color: isSelected ? '#6b7280' : '#9ca3af',
                  fontWeight: '600',
                  opacity: '1'
                }}
                onClick={handleBillingToggle}
                title={`Switch to ${billingPeriod === 'monthly' ? 'annual' : 'monthly'} billing`}
              >
                /{getPeriodText()}
              </button>
            )}
          </div>
          
          {billingPeriod === 'annually' && plan.has_annual_discount && plan.annual_discount_percent && displayPrice > 0 && (
            <div className="mt-1">
              <span className="inline-flex items-center bg-gradient-to-r from-green-100 to-emerald-100 text-green-800 text-sm font-bold px-3 py-1 rounded-full shadow-md border border-green-200">
                <span className="mr-1">💰</span>Save {plan.annual_discount_percent}%
              </span>
            </div>
          )}
          
          {/* Trial Badge - Under Price */}
          {plan.trial_days > 0 && displayPrice > 0 && (
            <div className="mt-1">
              <span className="inline-flex items-center bg-gradient-to-r from-purple-500 to-violet-500 text-white px-3 py-1 rounded-full text-xs font-bold shadow-md border border-purple-400/30">
                <span className="mr-1">🎁</span>{plan.trial_days}-day free trial
              </span>
            </div>
          )}
        </div>
      </div>

      {/* Limits Display */}
      <div className={`mb-3 rounded-xl p-2 backdrop-blur-sm transition-all duration-300 ${
        isSelected 
          ? 'bg-blue-50/80 border border-blue-200/50 shadow-md' 
          : featured
            ? 'bg-indigo-50/60 border border-indigo-200/40 shadow-md'
            : 'bg-gray-50/80 border border-gray-200/50 shadow-sm'
      }`}>
        <div className="grid grid-cols-3 gap-2 text-center">
          <div className="flex flex-col items-center">
            <div 
              className="text-base font-black mb-0.5"
              style={{
                color: isSelected ? '#1e40af' : '#111827',
                fontWeight: '900'
              }}
            >{limits.users}</div>
            <div 
              className="text-xs font-semibold uppercase tracking-wider"
              style={{
                color: isSelected ? '#6366f1' : '#6b7280',
                fontWeight: '600'
              }}
            >Users</div>
          </div>
          <div className="flex flex-col items-center">
            <div 
              className="text-base font-black mb-0.5"
              style={{
                color: isSelected ? '#1e40af' : '#111827',
                fontWeight: '900'
              }}
            >{limits.storage}</div>
            <div 
              className="text-xs font-semibold uppercase tracking-wider"
              style={{
                color: isSelected ? '#6366f1' : '#6b7280',
                fontWeight: '600'
              }}
            >Storage</div>
          </div>
          <div className="flex flex-col items-center">
            <div 
              className="text-base font-black mb-0.5"
              style={{
                color: isSelected ? '#1e40af' : '#111827',
                fontWeight: '900'
              }}
            >{limits.apiRequests}</div>
            <div 
              className="text-xs font-semibold uppercase tracking-wider"
              style={{
                color: isSelected ? '#6366f1' : '#6b7280',
                fontWeight: '600'
              }}
            >API</div>
          </div>
        </div>
      </div>

      {/* Features List */}
      <div className="flex-1 flex flex-col justify-between mb-4">
        <div className={`flex flex-col justify-start transition-all duration-300 overflow-hidden ${
          showAllFeatures ? 'max-h-none' : 'max-h-[180px]'
        }`}>
          <ul className="space-y-1.5">
            {(showAllFeatures ? features : features.slice(0, 5)).map((feature, featureIndex) => (
              <li key={featureIndex} className="flex items-start gap-3 text-sm group transition-all duration-200">
                <div className={`flex items-center justify-center w-4 h-4 rounded-full flex-shrink-0 mt-0.5 transition-all duration-200 ${
                  isSelected 
                    ? 'bg-blue-100 group-hover:bg-blue-200' 
                    : 'bg-green-100 group-hover:bg-green-200'
                }`}>
                  <CheckIcon 
                    className="w-2.5 h-2.5"
                    style={{
                      color: isSelected ? '#2563eb' : '#059669'
                    }}
                  />
                </div>
                <span 
                  className="leading-tight break-words"
                  style={{
                    color: isSelected ? '#374151' : '#4b5563',
                    fontWeight: '500'
                  }}
                >{feature}</span>
              </li>
            ))}
          </ul>
          
          {/* Show All Features when expanded */}
          {showAllFeatures && features.length > 5 && (
            <div className="mt-2 pt-2 border-t border-gray-100">
              <ul className="space-y-1.5">
                {features.slice(5).map((feature, featureIndex) => (
                  <li key={featureIndex + 5} className="flex items-start gap-3 text-sm group transition-all duration-200">
                    <div className={`flex items-center justify-center w-4 h-4 rounded-full flex-shrink-0 mt-0.5 transition-all duration-200 ${
                      isSelected 
                        ? 'bg-blue-100 group-hover:bg-blue-200' 
                        : 'bg-green-100 group-hover:bg-green-200'
                    }`}>
                      <CheckIcon 
                        className="w-2.5 h-2.5"
                        style={{
                          color: isSelected ? '#2563eb' : '#059669'
                        }}
                      />
                    </div>
                    <span 
                      className="leading-tight break-words"
                      style={{
                        color: isSelected ? '#374151' : '#4b5563',
                        fontWeight: '500'
                      }}
                    >{feature}</span>
                  </li>
                ))}
              </ul>
            </div>
          )}
          
          {/* Expandable Toggle - Fixed positioning */}
          {features.length > 5 && (
            <div className="mt-3 pt-2 border-t border-gray-50">
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  setShowAllFeatures(!showAllFeatures);
                }}
                className="flex items-center justify-center gap-2 w-full text-xs font-semibold transition-all duration-200 hover:opacity-80 py-1 rounded-md hover:bg-gray-50"
                style={{
                  color: isSelected ? '#2563eb' : '#059669',
                  fontWeight: '600'
                }}
              >
                <span>
                  {showAllFeatures 
                    ? `Show less features` 
                    : `Show ${features.length - 5} more features`
                  }
                </span>
                {showAllFeatures ? (
                  <ChevronUpIcon className="w-3 h-3" />
                ) : (
                  <ChevronDownIcon className="w-3 h-3" />
                )}
              </button>
            </div>
          )}
        </div>
      </div>

      {/* CTA Section */}
      <div className="mt-auto">
        {customAction ? (
          customAction
        ) : isCurrentPlan ? (
          <div className="w-full text-center px-6 py-4 bg-gray-100 text-gray-600 rounded-xl font-bold">
            Current Plan
          </div>
        ) : (
          <button
            onClick={(e) => {
              e.stopPropagation();
              handleCardClick();
            }}
            disabled={disabled || loading}
            className={`
              group relative w-full text-center px-6 py-4 text-base font-bold rounded-xl 
              transition-all duration-300 flex items-center justify-center 
              transform hover:scale-105 active:scale-95 overflow-hidden
              disabled:opacity-50 disabled:cursor-not-allowed disabled:hover:scale-100
              ${
                isSelected
                  ? 'bg-gradient-to-r from-blue-600 to-indigo-600 hover:from-blue-700 hover:to-indigo-700 shadow-xl hover:shadow-2xl text-white'
                  : 'bg-white border-2 border-gray-300 hover:border-blue-400 hover:bg-blue-50 shadow-lg hover:shadow-xl'
              }
            `}
            style={{
              color: isSelected ? '#ffffff' : '#111827'
            }}
          >
            {/* Button shine effect */}
            <div className="absolute inset-0 bg-gradient-to-r from-transparent via-white/20 to-transparent translate-x-[-100%] group-hover:translate-x-[100%] transition-transform duration-700" />
            
            <span className="relative font-bold tracking-wide">
              {loading ? 'Selecting...' : 
               upgradeContext === 'upgrade' ? 'Upgrade to Plan' :
               displayPrice === 0 ? 'Select Plan' : 'Select Plan'}
            </span>
            
            {/* Arrow icon */}
            {!loading && (
              <svg 
                className="relative w-5 h-5 ml-2 transition-transform duration-300 group-hover:translate-x-1" 
                fill="none" 
                viewBox="0 0 24 24" 
                stroke="currentColor"
              >
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 7l5 5m0 0l-5 5m5-5H6" />
              </svg>
            )}
          </button>
        )}
      </div>
    </div>
  );
};

export default PlanCard;
import React, { useState } from 'react';
import { CheckIcon, ChevronDownIcon, ChevronUpIcon } from '@heroicons/react/24/outline';
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
  variant?: 'default' | 'public';
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
  onBillingPeriodChange: _onBillingPeriodChange,
  variant = 'default'
}) => {
  const isPublic = variant === 'public';
  const [showAllFeatures, setShowAllFeatures] = useState(false);

  const getPrice = () => {
    if (!plan.price_cents) return 0;
    const basePrice = plan.price_cents / 100;

    if (plan.billing_cycle === 'yearly') {
      return basePrice / 12;
    }

    if (plan.billing_cycle === 'quarterly') {
      return basePrice / 3;
    }

    return basePrice;
  };

  const getPeriodText = () => {
    return 'month';
  };

  const getFeaturesList = () => {
    if (plan.features && typeof plan.features === 'object' && Object.keys(plan.features).length > 0) {
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

    return ['Dashboard Access', 'Basic Features', 'Email Support'];
  };

  const getLimitsDisplay = () => {
    if (plan.features && typeof plan.features === 'object') {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const features = plan.features as any;

      const users = features.max_users === 9999 ? 'Unlimited' : `${features.max_users || 2}`;
      const storage = features.storage_gb === 10000 ? 'Unlimited' :
                     features.storage_gb >= 1000 ? `${Math.floor(features.storage_gb / 1000)}TB` :
                     `${features.storage_gb || 1}GB`;

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
    e.stopPropagation();
    if (_onBillingPeriodChange) {
      const newPeriod = billingPeriod === 'monthly' ? 'annually' : 'monthly';
      _onBillingPeriodChange(newPeriod);
    }
  };

  // PUBLIC VARIANT - Completely separate render for public pages
  if (isPublic) {
    // Define all colors inline to avoid CSS override issues
    const cardBg = isSelected
      ? 'linear-gradient(135deg, #1e3a5f 0%, #1e293b 100%)'
      : featured
        ? 'linear-gradient(135deg, #312e81 0%, #1e1b4b 100%)'
        : 'linear-gradient(135deg, #1e293b 0%, #0f172a 100%)';
    const titleColor = isSelected ? '#93c5fd' : '#f8fafc';
    const descColor = '#94a3b8';
    const priceColor = displayPrice === 0 ? '#4ade80' : (isSelected ? '#93c5fd' : '#f8fafc');
    const featureColor = isSelected ? '#93c5fd' : '#e2e8f0';
    const limitValueColor = isSelected ? '#93c5fd' : '#f8fafc';

    // Use unique ID for scoped CSS styling
    const cardId = `plan-card-${plan.id}`;

    // CSS with !important to override any external styles
    const scopedStyles = `
      #${cardId} {
        position: relative !important;
        display: flex !important;
        flex-direction: column !important;
        width: 100% !important;
        max-width: 32rem !important;
        margin: 0 auto !important;
        padding: 2rem !important;
        border-radius: 1.5rem !important;
        min-height: 680px !important;
        cursor: pointer !important;
        transition: all 0.3s ease !important;
        transform: ${isSelected ? 'scale(1.05)' : 'scale(1)'} !important;
        background: ${cardBg} !important;
        background-color: ${isSelected ? '#1e3a5f' : featured ? '#312e81' : '#1e293b'} !important;
        border: ${isSelected ? '3px solid #3b82f6' : featured ? '2px solid #6366f1' : '2px solid rgba(100, 116, 139, 0.5)'} !important;
        box-shadow: ${isSelected ? '0 25px 50px -12px rgba(59, 130, 246, 0.4), 0 0 0 4px rgba(59, 130, 246, 0.1)' : featured ? '0 20px 40px -10px rgba(99, 102, 241, 0.3)' : '0 10px 40px -10px rgba(0, 0, 0, 0.5)'} !important;
        z-index: ${isSelected ? 20 : 1} !important;
        animation-delay: ${(index + 1) * 0.1}s !important;
        color: #f8fafc !important;
      }
    `;

    return (
      <>
        <style>{scopedStyles}</style>
        <div
          id={cardId}
          onClick={handleCardClick}
          data-public-plan-card="true"
          data-testid="plan-card"
        >
        {/* Badges */}
        <div style={{ position: 'absolute', top: '-1rem', left: '50%', transform: 'translateX(-50%)', display: 'flex', gap: '0.5rem', zIndex: 30 }}>
          {featured && (
            <span style={{
              background: 'linear-gradient(135deg, #3b82f6, #8b5cf6)',
              color: '#ffffff',
              padding: '0.5rem 1rem',
              borderRadius: '9999px',
              fontSize: '0.875rem',
              fontWeight: '700',
              boxShadow: '0 4px 15px rgba(59, 130, 246, 0.4)'
            }}>
              ⭐ Most Popular
            </span>
          )}
          {displayPrice === 0 && (
            <span style={{
              background: '#22c55e',
              color: '#ffffff',
              padding: '0.375rem 0.75rem',
              borderRadius: '9999px',
              fontSize: '0.75rem',
              fontWeight: '700',
              boxShadow: '0 4px 10px rgba(34, 197, 94, 0.3)'
            }}>
              🎯 Free
            </span>
          )}
        </div>

        {/* Header */}
        <div style={{ textAlign: 'center', marginBottom: '1.5rem', marginTop: '1rem' }}>
          <h3 style={{
            fontSize: '1.5rem',
            fontWeight: '800',
            marginBottom: '0.5rem',
            color: titleColor,
            textShadow: '0 1px 3px rgba(0,0,0,0.5)'
          }}>
            {plan.name}
          </h3>

          <p style={{
            fontSize: '0.875rem',
            color: descColor,
            marginBottom: '1rem',
            lineHeight: '1.4',
            textShadow: '0 1px 2px rgba(0,0,0,0.3)'
          }}>
            {plan.description || 'Professional subscription plan with comprehensive features'}
          </p>

          {/* Price */}
          <div style={{ marginBottom: '1rem' }}>
            <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'center' }}>
              <span style={{
                fontSize: '2.5rem',
                fontWeight: '800',
                color: priceColor,
                textShadow: '0 2px 4px rgba(0,0,0,0.4)'
              }}>
                {displayPrice === 0 ? 'Free' :
                 plan.currency === 'EUR' ? `€${displayPrice.toFixed(2)}` :
                 `$${Math.floor(displayPrice)}`}
              </span>
              {displayPrice > 0 && (
                <button
                  onClick={handleBillingToggle}
                  style={{
                    marginLeft: '0.5rem',
                    fontSize: '1rem',
                    fontWeight: '600',
                    color: '#64748b',
                    background: 'none',
                    border: 'none',
                    cursor: 'pointer'
                  }}
                >
                  /{getPeriodText()}
                </button>
              )}
            </div>

            {billingPeriod === 'annually' && plan.has_annual_discount && plan.annual_discount_percent && displayPrice > 0 && (
              <div style={{ marginTop: '0.5rem' }}>
                <span style={{
                  background: 'rgba(34, 197, 94, 0.2)',
                  color: '#4ade80',
                  padding: '0.25rem 0.75rem',
                  borderRadius: '9999px',
                  fontSize: '0.875rem',
                  fontWeight: '600'
                }}>
                  💰 Save {plan.annual_discount_percent}%
                </span>
              </div>
            )}

            {plan.trial_days > 0 && displayPrice > 0 && (
              <div style={{ marginTop: '0.5rem' }}>
                <span style={{
                  background: 'linear-gradient(135deg, #a855f7, #7c3aed)',
                  color: '#ffffff',
                  padding: '0.25rem 0.75rem',
                  borderRadius: '9999px',
                  fontSize: '0.75rem',
                  fontWeight: '600'
                }}>
                  🎁 {plan.trial_days}-day free trial
                </span>
              </div>
            )}
          </div>
        </div>

        {/* Limits Display */}
        <div style={{
          marginBottom: '1rem',
          padding: '0.75rem',
          borderRadius: '0.75rem',
          background: isSelected ? 'rgba(59, 130, 246, 0.15)' : 'rgba(71, 85, 105, 0.3)',
          border: isSelected ? '1px solid rgba(59, 130, 246, 0.3)' : '1px solid rgba(100, 116, 139, 0.2)'
        }}>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '0.5rem', textAlign: 'center' }}>
            <div>
              <div style={{ fontSize: '1rem', fontWeight: '800', color: limitValueColor, textShadow: '0 1px 2px rgba(0,0,0,0.4)' }}>
                {limits.users}
              </div>
              <div style={{ fontSize: '0.625rem', fontWeight: '600', textTransform: 'uppercase', color: '#94a3b8' }}>
                Users
              </div>
            </div>
            <div>
              <div style={{ fontSize: '1rem', fontWeight: '800', color: limitValueColor, textShadow: '0 1px 2px rgba(0,0,0,0.4)' }}>
                {limits.storage}
              </div>
              <div style={{ fontSize: '0.625rem', fontWeight: '600', textTransform: 'uppercase', color: '#94a3b8' }}>
                Storage
              </div>
            </div>
            <div>
              <div style={{ fontSize: '1rem', fontWeight: '800', color: limitValueColor, textShadow: '0 1px 2px rgba(0,0,0,0.4)' }}>
                {limits.apiRequests}
              </div>
              <div style={{ fontSize: '0.625rem', fontWeight: '600', textTransform: 'uppercase', color: '#94a3b8' }}>
                API
              </div>
            </div>
          </div>
        </div>

        {/* Features List */}
        <div style={{ flex: 1, marginBottom: '1rem' }}>
          <ul style={{ listStyle: 'none', padding: 0, margin: 0 }}>
            {(showAllFeatures ? features : features.slice(0, 5)).map((feature, featureIndex) => (
              <li key={featureIndex} style={{
                display: 'flex',
                alignItems: 'flex-start',
                gap: '0.75rem',
                marginBottom: '0.5rem',
                fontSize: '0.875rem'
              }}>
                <div style={{
                  width: '1rem',
                  height: '1rem',
                  borderRadius: '9999px',
                  background: isSelected ? 'rgba(56, 189, 248, 0.2)' : 'rgba(34, 197, 94, 0.2)',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  flexShrink: 0,
                  marginTop: '0.125rem'
                }}>
                  <CheckIcon style={{ width: '0.625rem', height: '0.625rem', color: isSelected ? '#38bdf8' : '#22c55e' }} />
                </div>
                <span style={{
                  color: featureColor,
                  fontWeight: '500',
                  textShadow: '0 1px 2px rgba(0,0,0,0.5)'
                }}>
                  {feature}
                </span>
              </li>
            ))}
          </ul>

          {features.length > 5 && (
            <button
              onClick={(e) => {
                e.stopPropagation();
                setShowAllFeatures(!showAllFeatures);
              }}
              style={{
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                gap: '0.5rem',
                width: '100%',
                marginTop: '0.75rem',
                padding: '0.5rem',
                background: 'none',
                border: 'none',
                borderTop: '1px solid rgba(100, 116, 139, 0.3)',
                color: isSelected ? '#38bdf8' : '#22c55e',
                fontSize: '0.75rem',
                fontWeight: '600',
                cursor: 'pointer'
              }}
            >
              <span>
                {showAllFeatures
                  ? 'Show less features'
                  : `Show ${features.length - 5} more features`
                }
              </span>
              {showAllFeatures ? (
                <ChevronUpIcon style={{ width: '0.75rem', height: '0.75rem' }} />
              ) : (
                <ChevronDownIcon style={{ width: '0.75rem', height: '0.75rem' }} />
              )}
            </button>
          )}
        </div>

        {/* CTA Button */}
        <div style={{ marginTop: 'auto' }}>
          {customAction ? (
            customAction
          ) : isCurrentPlan ? (
            <div style={{
              width: '100%',
              textAlign: 'center',
              padding: '1rem 1.5rem',
              borderRadius: '0.75rem',
              background: 'rgba(51, 65, 85, 0.5)',
              color: '#94a3b8',
              fontWeight: '700'
            }}>
              Current Plan
            </div>
          ) : (
            <button
              onClick={(e) => {
                e.stopPropagation();
                handleCardClick();
              }}
              disabled={disabled || loading}
              data-testid="plan-select-btn"
              style={{
                width: '100%',
                padding: '1rem 1.5rem',
                borderRadius: '0.75rem',
                fontSize: '1rem',
                fontWeight: '700',
                cursor: disabled || loading ? 'not-allowed' : 'pointer',
                opacity: disabled || loading ? 0.5 : 1,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                gap: '0.5rem',
                transition: 'all 0.2s ease',
                background: isSelected
                  ? 'linear-gradient(135deg, #3b82f6, #8b5cf6)'
                  : featured
                    ? 'linear-gradient(135deg, #6366f1, #8b5cf6)'
                    : displayPrice === 0
                      ? 'linear-gradient(135deg, #22c55e, #16a34a)'
                      : 'linear-gradient(135deg, #3b82f6, #2563eb)',
                color: '#ffffff',
                border: 'none',
                boxShadow: isSelected
                  ? '0 10px 25px -5px rgba(59, 130, 246, 0.5)'
                  : displayPrice === 0
                    ? '0 8px 20px -5px rgba(34, 197, 94, 0.4)'
                    : '0 8px 20px -5px rgba(59, 130, 246, 0.4)'
              }}
            >
              <span>
                {loading ? 'Selecting...' :
                 upgradeContext === 'upgrade' ? 'Upgrade to Plan' :
                 displayPrice === 0 ? 'Get Started Free' : 'Select Plan'}
              </span>
              {!loading && (
                <svg
                  style={{ width: '1.25rem', height: '1.25rem' }}
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
      </>
    );
  }

  // DEFAULT VARIANT - Original implementation for authenticated pages
  return (
    <div
      className={`
        group relative flex flex-col w-full max-w-lg mx-auto cursor-pointer
        rounded-3xl p-8 transition-all duration-500 transform-gpu
        min-h-[680px] overflow-visible bg-theme-surface
        ${
          isSelected
            ? 'ring-4 ring-theme-primary ring-offset-4 ring-offset-theme-primary/10 scale-110 shadow-2xl z-20 hover:scale-110 border-2 border-theme-primary'
            : featured
              ? 'ring-1 ring-theme-primary/30 ring-offset-1 shadow-2xl scale-100 hover:scale-105 hover:shadow-xl border-primary'
              : 'border border-theme hover:scale-105 scale-100 shadow-lg hover:shadow-xl hover:border-theme'
        }
        ${className}
      `}
      onClick={handleCardClick}
      data-testid="plan-card"
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
              ? 'bg-gradient-to-br from-theme-primary/10 via-theme-primary/5 to-theme-info/10 opacity-100'
              : featured
                ? 'bg-gradient-to-br from-theme-primary/5 via-theme-surface to-theme-info/5 opacity-90'
                : 'bg-gradient-to-br from-theme-background/80 via-theme-surface to-theme-background/60 opacity-70'
          }
        `}
      />

      {/* Subtle Decorative Elements */}
      <div className="absolute top-0 right-0 w-24 h-24 bg-gradient-to-br from-theme-primary/10 to-transparent rounded-full -mr-12 -mt-12 transition-transform duration-700 group-hover:scale-110" />
      <div className="absolute bottom-0 left-0 w-20 h-20 bg-gradient-to-tr from-theme-info/10 to-transparent rounded-full -ml-10 -mb-10 transition-transform duration-700 group-hover:scale-110" />

      {/* Selected Plan Glow Effect */}
      {isSelected && (
        <div className="absolute inset-0 rounded-3xl -z-20">
          <div className="absolute inset-0 bg-gradient-to-r from-theme-primary via-theme-primary to-theme-info rounded-3xl blur-lg opacity-30"></div>
          <div className="absolute inset-2 bg-gradient-to-r from-theme-primary/80 via-theme-primary to-theme-info/80 rounded-3xl blur-md opacity-20"></div>
        </div>
      )}

      {/* Top Badges */}
      <div className="absolute -top-4 left-1/2 transform -translate-x-1/2 z-30 flex items-center justify-center gap-2 max-w-full px-2">
        {featured && (
          <div className="relative">
            <div className="absolute inset-0 bg-gradient-to-r from-theme-primary to-theme-info rounded-full blur-sm opacity-60"></div>
            <span className="relative bg-gradient-to-r from-theme-primary to-theme-info text-white px-4 py-2 rounded-full text-sm font-bold shadow-xl border border-theme-primary/30 whitespace-nowrap">
              <span className="mr-2">⭐</span>Most Popular
            </span>
          </div>
        )}

        {displayPrice === 0 && (
          <span className="bg-theme-success text-white px-3 py-1.5 rounded-full text-xs font-bold shadow-lg border border-theme-success/30 whitespace-nowrap">
            <span className="mr-1">🎯</span>Free
          </span>
        )}

        {billingPeriod === 'annually' && plan.has_annual_discount && plan.annual_discount_percent && plan.annual_discount_percent >= 20 && (
          <span className="bg-gradient-to-r from-orange-500 to-red-500 text-white px-3 py-1.5 rounded-full text-xs font-bold shadow-lg border border-theme-warning/30 whitespace-nowrap">
            <span className="mr-1">💰</span>Best Value
          </span>
        )}
      </div>

      {/* Header */}
      <div className="text-center mb-4 mt-4">
        <h3 className={`text-2xl font-black mb-2 tracking-tight ${isSelected ? 'text-theme-link' : 'text-theme-primary'}`}>
          {plan.name}
        </h3>

        <p className={`text-sm line-clamp-2 mb-1 leading-none max-w-sm mx-auto font-medium ${isSelected ? 'text-theme-secondary' : 'text-theme-muted'}`} style={{ lineHeight: '1.1' }}>
          {plan.description || 'Professional subscription plan with comprehensive features'}
        </p>

        {/* Price Display */}
        <div className="mb-4">
          <div className="flex items-baseline justify-center mb-1">
            <span className={`text-4xl font-black tracking-tight ${isSelected ? 'text-theme-link' : displayPrice === 0 ? 'text-theme-success' : 'text-theme-primary'}`}>
              {displayPrice === 0 ? 'Free' :
               plan.currency === 'EUR' ? `€${displayPrice.toFixed(2)}` :
               `$${Math.floor(displayPrice)}`}
            </span>
            {displayPrice > 0 && (
              <button
                className={`ml-2 text-lg font-semibold self-end pb-1 hover:underline cursor-pointer transition-all duration-200 hover:opacity-80 ${isSelected ? 'text-theme-muted' : 'text-theme-tertiary'}`}
                onClick={handleBillingToggle}
                title={`Switch to ${billingPeriod === 'monthly' ? 'annual' : 'monthly'} billing`}
              >
                /{getPeriodText()}
              </button>
            )}
          </div>

          {billingPeriod === 'annually' && plan.has_annual_discount && plan.annual_discount_percent && displayPrice > 0 && (
            <div className="mt-1">
              <span className="inline-flex items-center bg-theme-success/20 text-theme-success text-sm font-bold px-3 py-1 rounded-full shadow-md border border-theme-success/30">
                <span className="mr-1">💰</span>Save {plan.annual_discount_percent}%
              </span>
            </div>
          )}

          {plan.trial_days > 0 && displayPrice > 0 && (
            <div className="mt-1">
              <span className="inline-flex items-center bg-gradient-to-r from-purple-500 to-violet-500 text-white px-3 py-1 rounded-full text-xs font-bold shadow-md border border-theme-interactive-primary/30">
                <span className="mr-1">🎁</span>{plan.trial_days}-day free trial
              </span>
            </div>
          )}
        </div>
      </div>

      {/* Limits Display */}
      <div className={`mb-3 rounded-xl p-2 backdrop-blur-sm transition-all duration-300 ${
        isSelected
          ? 'bg-theme-primary/10 border border-theme-primary/20 shadow-md'
          : featured
            ? 'bg-theme-info/10 border border-theme-info/20 shadow-md'
            : 'bg-theme-surface/80 border border-theme/50 shadow-sm'
      }`}>
        <div className="grid grid-cols-3 gap-2 text-center">
          <div className="flex flex-col items-center">
            <div className={`text-base font-black mb-0.5 ${isSelected ? 'text-theme-link' : 'text-theme-primary'}`}>
              {limits.users}
            </div>
            <div className={`text-xs font-semibold uppercase tracking-wider ${isSelected ? 'text-theme-info' : 'text-theme-muted'}`}>
              Users
            </div>
          </div>
          <div className="flex flex-col items-center">
            <div className={`text-base font-black mb-0.5 ${isSelected ? 'text-theme-link' : 'text-theme-primary'}`}>
              {limits.storage}
            </div>
            <div className={`text-xs font-semibold uppercase tracking-wider ${isSelected ? 'text-theme-info' : 'text-theme-muted'}`}>
              Storage
            </div>
          </div>
          <div className="flex flex-col items-center">
            <div className={`text-base font-black mb-0.5 ${isSelected ? 'text-theme-link' : 'text-theme-primary'}`}>
              {limits.apiRequests}
            </div>
            <div className={`text-xs font-semibold uppercase tracking-wider ${isSelected ? 'text-theme-info' : 'text-theme-muted'}`}>
              API
            </div>
          </div>
        </div>
      </div>

      {/* Features List */}
      <div className="flex-1 flex flex-col justify-between mb-4">
        <div className={`flex flex-col justify-start transition-all duration-300 overflow-hidden ${showAllFeatures ? 'max-h-none' : 'max-h-[180px]'}`}>
          <ul className="space-y-1.5">
            {(showAllFeatures ? features : features.slice(0, 5)).map((feature, featureIndex) => (
              <li key={featureIndex} className="flex items-start gap-3 text-sm group transition-all duration-200">
                <div className={`flex items-center justify-center w-4 h-4 rounded-full flex-shrink-0 mt-0.5 transition-all duration-200 ${
                  isSelected
                    ? 'bg-theme-info/20 group-hover:bg-theme-info/30'
                    : 'bg-theme-success/20 group-hover:bg-theme-success/30'
                }`}>
                  <CheckIcon className={`w-2.5 h-2.5 ${isSelected ? 'text-theme-info' : 'text-theme-success'}`} />
                </div>
                <span className={`leading-tight break-words font-medium ${isSelected ? 'text-theme-secondary' : 'text-theme-muted'}`}>
                  {feature}
                </span>
              </li>
            ))}
          </ul>

          {showAllFeatures && features.length > 5 && (
            <div className="mt-2 pt-2 border-t border-theme">
              <ul className="space-y-1.5">
                {features.slice(5).map((feature, featureIndex) => (
                  <li key={featureIndex + 5} className="flex items-start gap-3 text-sm group transition-all duration-200">
                    <div className={`flex items-center justify-center w-4 h-4 rounded-full flex-shrink-0 mt-0.5 transition-all duration-200 ${
                      isSelected
                        ? 'bg-theme-info/20 group-hover:bg-theme-info/30'
                        : 'bg-theme-success/20 group-hover:bg-theme-success/30'
                    }`}>
                      <CheckIcon className={`w-2.5 h-2.5 ${isSelected ? 'text-theme-info' : 'text-theme-success'}`} />
                    </div>
                    <span className={`leading-tight break-words font-medium ${isSelected ? 'text-theme-secondary' : 'text-theme-muted'}`}>
                      {feature}
                    </span>
                  </li>
                ))}
              </ul>
            </div>
          )}

          {features.length > 5 && (
            <div className="mt-3 pt-2 border-t border-theme/50">
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  setShowAllFeatures(!showAllFeatures);
                }}
                className={`flex items-center justify-center gap-2 w-full text-xs font-semibold transition-all duration-200 hover:opacity-80 py-1 rounded-md hover:bg-theme-surface ${isSelected ? 'text-theme-info' : 'text-theme-success'}`}
              >
                <span>
                  {showAllFeatures
                    ? 'Show less features'
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
          <div className="w-full text-center px-6 py-4 rounded-xl font-bold bg-theme-surface text-theme-muted">
            Current Plan
          </div>
        ) : (
          <button
            onClick={(e) => {
              e.stopPropagation();
              handleCardClick();
            }}
            disabled={disabled || loading}
            data-testid="plan-select-btn"
            className={`
              group relative w-full text-center px-6 py-4 text-base font-bold rounded-xl
              transition-all duration-300 flex items-center justify-center
              transform hover:scale-105 active:scale-95 overflow-hidden
              disabled:opacity-50 disabled:cursor-not-allowed disabled:hover:scale-100
              ${
                isSelected
                  ? 'bg-gradient-to-r from-theme-primary to-theme-info hover:from-theme-primary-hover hover:to-theme-info shadow-xl hover:shadow-2xl text-white'
                  : 'bg-theme-surface border-2 border-theme hover:border-theme-primary hover:bg-theme-primary/5 shadow-lg hover:shadow-xl text-theme-primary'
              }
            `}
          >
            <div className="absolute inset-0 bg-gradient-to-r from-transparent via-white/20 to-transparent translate-x-[-100%] group-hover:translate-x-[100%] transition-transform duration-700" />

            <span className="relative font-bold tracking-wide">
              {loading ? 'Selecting...' :
               upgradeContext === 'upgrade' ? 'Upgrade to Plan' :
               displayPrice === 0 ? 'Select Plan' : 'Select Plan'}
            </span>

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

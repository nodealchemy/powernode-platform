import React, { useState, useEffect } from 'react';

import { Link, useNavigate } from 'react-router-dom';

import { plansApi, Plan } from '@/features/plans/services/plansApi';

import { 
  CheckIcon, 
  ArrowRightIcon,
  ShieldCheckIcon,
  ClockIcon,
  ScaleIcon,
  XMarkIcon
} from '@heroicons/react/24/outline';
import { PlanCard } from '@/features/plans/components/PlanCard';

import { AnnualSavingsCalculator } from '@/features/plans/components/AnnualSavingsCalculator';


export const PlanSelectionPage: React.FC = () => {
  const navigate = useNavigate();
  const [availablePlans, setAvailablePlans] = useState<Plan[]>([]);
  const [plansLoading, setPlansLoading] = useState(false);
  const [selectedPlanId, setSelectedPlanId] = useState<string | null>(null);
  const [billingCycle, setBillingCycle] = useState<'monthly' | 'yearly'>('monthly');
  const [showComparison, setShowComparison] = useState(false);
  const [plansToCompare, setPlansToCompare] = useState<string[]>([]);

  useEffect(() => {

 void loadAvailablePlans();
  }, []);

  const loadAvailablePlans = async () => {
    try {
      setPlansLoading(true);
      const response = await plansApi.getPublicPlans();
      if (response.success) {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        setAvailablePlans((response.data as any).plans);
        // Auto-select the first plan or a featured plan
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        if ((response.data as any).plans.length > 0) {
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          const featuredPlan = (response.data as any).plans.find((plan: any) => plan.name.toLowerCase().includes('pro') || plan.name.toLowerCase().includes('standard'));
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          setSelectedPlanId(featuredPlan?.id || (response.data as any).plans[0].id);
        }
      }
    } catch (error: unknown) {
    } finally {
      setPlansLoading(false);
    }
  };

  const calculatePlanPrice = (plan: Plan, cycle: 'monthly' | 'yearly'): string => {
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
    // Note: Removed promotional discount application for sticky bottom display
    
    const amount = priceCents / 100;
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: plan.currency
    }).format(amount);
  };

  const getMonthlyPrice = (plan: Plan): string => {
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
    // Note: Removed promotional discount application for consistency
    
    const amount = monthlyCents / 100;
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: plan.currency
    }).format(amount);
  };

  const handlePlanSelection = (plan: Plan) => {
    setSelectedPlanId(plan.id);
  };

  const handleBillingPeriodChange = (period: 'monthly' | 'annually') => {
    setBillingCycle(period === 'annually' ? 'yearly' : 'monthly');
  };

  const handleContinue = () => {
    if (selectedPlanId) {
      navigate(`/register?plan=${selectedPlanId}&billing=${billingCycle}`);
    }
  };

  const getSelectedPlan = (): Plan | null => {
    return availablePlans.find(plan => plan.id === selectedPlanId) || null;
  };

  const isPlanPopular = (plan: Plan): boolean => {
    return plan.name.toLowerCase().includes('pro') || plan.name.toLowerCase().includes('standard');
  };

  const getPlanFeatures = (plan: Plan): string[] => {
    // Use actual plan features if available, fallback to tier-based features
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

  const getAllPlanFeatures = (): string[] => {
    // Get all unique features across all plans for comparison
    const allFeatures = new Set<string>();
    availablePlans.forEach(plan => {
      getPlanFeatures(plan).forEach(feature => {
        allFeatures.add(feature);
      });
    });
    return Array.from(allFeatures).sort();
  };

  const togglePlanComparison = (planId: string) => {
    setPlansToCompare(prev => {
      if (prev.includes(planId)) {
        return prev.filter(id => id !== planId);
      } else if (prev.length < 3) { // Limit to 3 plans for comparison
        return [...prev, planId];
      }
      return prev;
    });
  };

  const startComparison = () => {
    if (plansToCompare.length >= 2) {
      setShowComparison(true);
    }
  };

  const planHasFeature = (plan: Plan, feature: string): boolean => {
    return getPlanFeatures(plan).includes(feature);
  };



  if (plansLoading) {
    return (
      <div className="min-h-screen bg-theme-background-secondary flex items-center justify-center">
        <div className="text-center">
          <div className="animate-spin h-12 w-12 border-4 border-theme-interactive-primary border-t-transparent rounded-full mx-auto mb-4"></div>
          <p className="text-theme-secondary">Loading plans...</p>
        </div>
      </div>
    );
  }

  return (
    <div className="theme-public bg-public-gradient">
      {/* Header */}
      <header className="public-header">
        <div className="container">
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '1rem 0' }}>
            <Link to="/" style={{ display: 'flex', alignItems: 'center', gap: '0.75rem', textDecoration: 'none' }}>
              <div style={{ width: '2.5rem', height: '2.5rem', background: 'linear-gradient(135deg, var(--public-primary), var(--public-secondary))', borderRadius: '0.75rem', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'white', fontWeight: 'bold', fontSize: '1.25rem' }}>
                P
              </div>
              <div>
                <div style={{ fontSize: '1.5rem', fontWeight: '700', color: 'var(--public-text-primary)', marginBottom: '0', lineHeight: '1.2' }}>
                  Powernode
                </div>
                <div style={{fontSize: '0.75rem', fontWeight: '500', color: 'var(--public-text-secondary)', marginTop: '0', marginBottom: '0'}}>Choose your plan</div>
              </div>
            </Link>
            
            <div style={{ display: 'flex', alignItems: 'center', gap: '1.5rem' }}>
              {plansToCompare.length >= 2 && (
                <button
                  onClick={() => startComparison?.()}
                  className="inline-flex items-center space-x-2 px-4 py-2.5 bg-emerald-500 hover:bg-emerald-600 text-white text-sm font-semibold rounded-lg transition-all duration-200 transform hover:scale-105 shadow-lg hover:shadow-xl"
                >
                  <ScaleIcon className="h-4 w-4" />
                  <span>Compare {plansToCompare.length} Plans</span>
                </button>
              )}
              <Link
                to="/login"
                style={{ color: 'var(--public-text-primary)', textDecoration: 'none', fontWeight: '500' }}
              >
                Sign in
              </Link>
            </div>
          </div>
        </div>
      </header>

      {/* Enhanced Hero Section */}
      <section className="relative overflow-hidden pt-20 pb-12">
        {/* Background Decorations */}
        <div className="absolute inset-0">
          <div className="absolute top-40 left-10 w-72 h-72 bg-blue-400/10 rounded-full blur-3xl"></div>
          <div className="absolute top-20 right-20 w-96 h-96 bg-purple-400/10 rounded-full blur-3xl"></div>
          <div className="absolute bottom-20 left-1/2 w-80 h-80 bg-indigo-400/10 rounded-full blur-3xl transform -translate-x-1/2"></div>
        </div>
        
        <div className="relative max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 text-center">
          <div className="max-w-4xl mx-auto">
            <h1 className="text-5xl md:text-6xl lg:text-7xl font-extrabold leading-tight mb-8" style={{color: 'var(--public-text-primary)'}}>
              <span>
                Choose the perfect
              </span>
              <br />
              <span className="bg-gradient-to-r from-blue-400 via-blue-300 to-indigo-400 bg-clip-text text-transparent">
                plan for your team
              </span>
            </h1>
            
            <p className="text-xl md:text-2xl max-w-3xl mx-auto leading-relaxed mb-12" style={{color: 'var(--public-text-secondary)'}}>
              Start your journey with Powernode. Powerful features, transparent pricing, 
              and world-class support to help your business grow.
            </p>
          </div>
          
          {/* Modern Trust Indicators */}
          <div className="flex flex-wrap items-center justify-center gap-8 max-w-4xl mx-auto">
            <div className="flex items-center space-x-3 surface px-4 py-3 rounded-full">
              <div className="w-8 h-8 bg-emerald-500/20 rounded-full flex items-center justify-center">
                <ShieldCheckIcon className="h-4 w-4 text-emerald-400" />
              </div>
              <span className="text-sm font-semibold" style={{color: 'var(--public-text-primary)'}}>30-day money back</span>
            </div>
            
            <div className="flex items-center space-x-3 surface px-4 py-3 rounded-full">
              <div className="w-8 h-8 bg-theme-info/20 rounded-full flex items-center justify-center">
                <ClockIcon className="h-4 w-4 text-blue-400" />
              </div>
              <span className="text-sm font-semibold" style={{color: 'var(--public-text-primary)'}}>Free trial included</span>
            </div>
            
            <div className="flex items-center space-x-3 surface px-4 py-3 rounded-full">
              <div className="w-8 h-8 bg-theme-interactive-primary/20 rounded-full flex items-center justify-center">
                <CheckIcon className="h-4 w-4 text-purple-400" />
              </div>
              <span className="text-sm font-semibold" style={{color: 'var(--public-text-primary)'}}>No setup fees</span>
            </div>
          </div>
        </div>
      </section>

      {/* Modern Billing Toggle Section */}
      <section className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 mb-16 relative z-30">
        <div className="flex flex-col items-center">
          {/* Enhanced Billing Toggle */}
          <div className="relative mb-8">
            <div className="surface-lg rounded-2xl p-2 shadow-xl transform transition-all duration-300 hover:scale-105">
              <div className="flex items-center space-x-2">
                <button
                  onClick={() => setBillingCycle('monthly')}
                  className={`relative px-6 py-3 rounded-xl text-sm font-semibold transition-all duration-300 ${
                    billingCycle === 'monthly'
                      ? 'bg-white dark:bg-slate-700 text-slate-800 dark:text-white shadow-lg'
                      : 'text-slate-600 dark:text-slate-400 hover:text-slate-800 dark:hover:text-slate-200'
                  }`}
                >
                  Monthly billing
                </button>
                <button
                  onClick={() => setBillingCycle('yearly')}
                  className={`relative px-6 py-3 rounded-xl text-sm font-semibold transition-all duration-300 ${
                    billingCycle === 'yearly'
                      ? 'bg-white dark:bg-slate-700 text-slate-800 dark:text-white shadow-lg'
                      : 'text-slate-600 dark:text-slate-400 hover:text-slate-800 dark:hover:text-slate-200'
                  }`}
                >
                  <span>Annual billing</span>
                  {availablePlans.some(p => p.has_annual_discount) && (
                    <span className="ml-2 px-2.5 py-1 bg-gradient-to-r from-emerald-400 to-green-400 text-white rounded-full text-xs font-bold shadow-md">
                      Save up to {Math.max(...availablePlans.map(p => p.annual_discount_percent || 0))}%
                    </span>
                  )}
                </button>
              </div>
            </div>
          </div>
          
          {/* Annual Savings Animation */}
          {billingCycle === 'yearly' && availablePlans.some(p => p.has_annual_discount) && (
            <div className="mb-6 text-center transform transition-all duration-500 ease-out">
              <div className="inline-flex items-center space-x-2 bg-gradient-to-r from-emerald-50 to-green-50 dark:from-emerald-900/20 dark:to-green-900/20 px-4 py-3 rounded-full border border-emerald-200/50 dark:border-emerald-700/50">
                <div className="w-6 h-6 bg-gradient-to-r from-emerald-400 to-green-400 rounded-full flex items-center justify-center animate-pulse">
                  <span className="text-white text-sm">💰</span>
                </div>
                <p className="text-sm font-semibold text-emerald-700 dark:text-emerald-300">
                  You're saving money with annual billing!
                </p>
              </div>
            </div>
          )}
          
          {/* Comparison Helper */}
          {plansToCompare.length > 0 && (
            <div className="text-center bg-white/50 dark:bg-slate-800/50 backdrop-blur-sm px-6 py-4 rounded-xl border border-slate-200/50 dark:border-slate-600/50">
              <div className="flex items-center justify-center space-x-3 mb-2">
                <div className="w-2 h-2 bg-blue-400 rounded-full animate-pulse"></div>
                <p className="text-sm font-medium text-slate-700 dark:text-slate-300">
                  {plansToCompare.length} plan{plansToCompare.length > 1 ? 's' : ''} selected for comparison
                </p>
              </div>
              {plansToCompare.length >= 2 ? (
                <button
                  onClick={() => startComparison?.()}
                  className="inline-flex items-center space-x-2 text-sm font-semibold text-theme-info dark:text-blue-400 hover:text-theme-info dark:hover:text-blue-300 transition-colors duration-200"
                >
                  <span>Compare now</span>
                  <ArrowRightIcon className="h-4 w-4" />
                </button>
              ) : (
                <p className="text-xs text-slate-500 dark:text-slate-400">
                  Select at least 2 plans to compare features
                </p>
              )}
            </div>
          )}
        </div>
      </section>

      {/* Enhanced Plans Grid */}
      <section className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 mb-20">
        <div className="text-center mb-12">
          <h2 className="text-3xl md:text-4xl font-bold mb-4" style={{color: 'var(--public-text-primary)'}}>
            Simple, transparent pricing
          </h2>
          <p className="text-lg max-w-2xl mx-auto" style={{color: 'var(--public-text-secondary)'}}>
            Choose the plan that's right for you. Upgrade or downgrade at any time.
          </p>
        </div>
        
        <div className="grid lg:grid-cols-3 gap-8 max-w-6xl mx-auto items-start px-4 pt-8">
          {availablePlans.map((plan, index) => (
            <div 
              key={plan.id} 
              className="relative h-full flex flex-col group"
              style={{ 
                animationDelay: `${index * 150}ms`,
                animation: 'fadeInUp 0.6s ease-out forwards',
                padding: '16px', // Increased padding for better scale clearance
                zIndex: selectedPlanId === plan.id ? 20 : 10
              }}
            >
              {/* Compare Checkbox Above Card - Positioned higher to avoid zoom overlap */}
              <div className="mb-12 flex justify-start">
                <label className="flex items-center space-x-2 cursor-pointer group/compare">
                  <div className="relative">
                    <input
                      type="checkbox"
                      checked={plansToCompare.includes(plan.id)}
                      onChange={(e) => {
                        e.stopPropagation();
                        togglePlanComparison(plan.id);
                      }}
                      disabled={!plansToCompare.includes(plan.id) && plansToCompare.length >= 3}
                      className="w-5 h-5 text-theme-info bg-white border-2 border-slate-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 transition-all duration-200"
                    />
                  </div>
                  <span className="text-sm font-medium text-slate-600 group-hover/compare:text-slate-800 transition-colors duration-200">
                    Compare {plan.name}
                  </span>
                </label>
              </div>

              <PlanCard
                plan={plan}
                billingPeriod={billingCycle === 'yearly' ? 'annually' : 'monthly'}
                index={index}
                featured={isPlanPopular(plan)}
                onSelect={handlePlanSelection}
                isSelected={selectedPlanId === plan.id}
                onBillingPeriodChange={handleBillingPeriodChange}
                variant="public"
              />
            </div>
          ))}
        </div>
      </section>

      {/* Modern Sticky CTA Section */}
      {selectedPlanId && (
        <div className="sticky bottom-0 z-40 bg-white/95 dark:bg-slate-900/95 backdrop-blur-lg border-t border-slate-200/50 dark:border-slate-700/50 mt-20">
          <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
            <div className="flex flex-col lg:flex-row items-center justify-between gap-6">
              {/* Plan Summary */}
              <div className="flex items-center space-x-6">
                <div className="flex items-center space-x-4">
                  <div className="w-12 h-12 rounded-xl flex items-center justify-center" style={{ background: 'linear-gradient(135deg, #22c55e, #16a34a)' }}>
                    <CheckIcon className="h-6 w-6 text-white" />
                  </div>
                  <div>
                    <div className="font-semibold text-slate-800 dark:text-white">
                      {getSelectedPlan()?.name} Plan Selected
                    </div>
                    <div className="text-sm text-slate-600 dark:text-slate-400">
                      Billed {billingCycle}
                      {getSelectedPlan()?.trial_days && getSelectedPlan()!.trial_days > 0 && (
                        <span className="ml-2 px-2 py-0.5 bg-gradient-to-r from-emerald-500 to-green-500 text-white rounded-full text-xs font-bold shadow-sm">
                          {getSelectedPlan()!.trial_days} day trial
                        </span>
                      )}
                    </div>
                  </div>
                </div>
                
                <div className="hidden sm:block w-px h-12 bg-slate-200 dark:bg-slate-600"></div>
                
                <div className="text-center sm:text-left">
                  <div className="text-2xl font-bold text-slate-800 dark:text-white">
                    {calculatePlanPrice(getSelectedPlan()!, billingCycle)}
                  </div>
                  <div className="text-sm text-slate-500 dark:text-slate-400">
                    per {billingCycle === 'yearly' ? 'year' : 'month'}
                  </div>
                </div>
              </div>

              {/* CTA Button */}
              <div className="flex flex-col items-center space-y-3">
                <button
                  onClick={() => handleContinue?.()}
                  className="inline-flex items-center justify-center space-x-3 text-white font-semibold px-8 py-4 rounded-xl transition-all duration-200 transform hover:scale-105 min-w-[200px]"
                  style={{
                    background: 'linear-gradient(135deg, #3b82f6, #8b5cf6)',
                    boxShadow: '0 10px 25px -5px rgba(59, 130, 246, 0.5)',
                  }}
                >
                  <span>Get Started</span>
                  <ArrowRightIcon className="h-5 w-5" />
                </button>
                
                <div className="flex items-center space-x-4 text-xs text-slate-500 dark:text-slate-400">
                  <span className="flex items-center space-x-1">
                    <CheckIcon className="h-3 w-3" />
                    <span>No credit card required</span>
                  </span>
                  <span className="flex items-center space-x-1">
                    <CheckIcon className="h-3 w-3" />
                    <span>Cancel anytime</span>
                  </span>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Additional Selected Plan Details */}
      {selectedPlanId && (
        <section className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 mb-20">
          <div className="bg-gradient-to-r from-blue-50 to-purple-50 dark:from-slate-800 dark:to-slate-700 rounded-2xl p-8 border border-slate-200/50 dark:border-slate-600/50">
            <div className="text-center mb-6">
              <h3 className="text-2xl font-bold text-slate-800 dark:text-white mb-3">
                Ready to get started with {getSelectedPlan()?.name}?
              </h3>
              <p className="text-slate-600 dark:text-slate-300 max-w-2xl mx-auto">
                You'll be able to review and modify your subscription after creating your account. 
                Start your free trial and see how Powernode can transform your workflow.
              </p>
            </div>
            
            {/* Annual Savings Calculator for Selected Plan */}
            {billingCycle === 'monthly' && getSelectedPlan()?.has_annual_discount && (
              <div className="mt-6">
                <AnnualSavingsCalculator plan={getSelectedPlan()!} />
              </div>
            )}
          </div>
        </section>
      )}

      {/* Modern FAQ/Additional Info Section */}
      <section className="max-w-5xl mx-auto px-4 sm:px-6 lg:px-8 mb-20">
        <div className="bg-gradient-to-r from-slate-50 to-blue-50/50 dark:from-slate-800/50 dark:to-slate-700/50 rounded-3xl p-12 border border-slate-200/30 dark:border-slate-600/30 backdrop-blur-sm">
          <div className="text-center mb-10">
            <h3 className="text-3xl font-bold text-slate-800 dark:text-white mb-4">
              Questions? We're here to help
            </h3>
            <p className="text-lg text-slate-600 dark:text-slate-300 max-w-2xl mx-auto">
              Our team is ready to support you every step of the way. Get answers, compare plans, or reach out directly.
            </p>
          </div>
          
          <div className="grid md:grid-cols-3 gap-8">
            <button 
              className="group bg-white/80 dark:bg-slate-700/50 backdrop-blur-sm rounded-2xl p-6 border border-slate-200/50 dark:border-slate-600/50 hover:border-blue-300 dark:hover:border-theme-info transition-all duration-300 hover:shadow-xl hover:shadow-blue-500/10 transform hover:-translate-y-1"
              disabled
            >
              <div className="w-12 h-12 bg-gradient-to-r from-blue-500 to-blue-600 rounded-xl flex items-center justify-center mb-4 group-hover:scale-110 transition-transform duration-300">
                <span className="text-white text-xl">📧</span>
              </div>
              <h4 className="font-semibold text-slate-800 dark:text-white mb-2 group-hover:text-theme-info dark:group-hover:text-blue-400 transition-colors duration-300">
                Contact Support
              </h4>
              <p className="text-sm text-slate-600 dark:text-slate-300">
                Get personalized help from our expert team. We typically respond within 2 hours.
              </p>
            </button>
            
            <button 
              onClick={() => {
                // Auto-select all plans for comparison if none selected
                if (plansToCompare.length === 0) {
                  setPlansToCompare(availablePlans.map(plan => plan.id).slice(0, 3));
                }
                setShowComparison(true);
              }}
              className="group bg-white/80 dark:bg-slate-700/50 backdrop-blur-sm rounded-2xl p-6 border border-slate-200/50 dark:border-slate-600/50 hover:border-purple-300 dark:hover:border-theme-interactive-primary transition-all duration-300 hover:shadow-xl hover:shadow-purple-500/10 transform hover:-translate-y-1 text-left"
            >
              <div className="w-12 h-12 bg-gradient-to-r from-purple-500 to-purple-600 rounded-xl flex items-center justify-center mb-4 group-hover:scale-110 transition-transform duration-300">
                <ScaleIcon className="h-6 w-6 text-white" />
              </div>
              <h4 className="font-semibold text-slate-800 dark:text-white mb-2 group-hover:text-theme-interactive-primary dark:group-hover:text-purple-400 transition-colors duration-300">
                Compare Plans
              </h4>
              <p className="text-sm text-slate-600 dark:text-slate-300">
                See a detailed side-by-side comparison of features and pricing across all plans.
              </p>
            </button>
            
            <button 
              className="group bg-white/80 dark:bg-slate-700/50 backdrop-blur-sm rounded-2xl p-6 border border-slate-200/50 dark:border-slate-600/50 hover:border-emerald-300 dark:hover:border-emerald-500 transition-all duration-300 hover:shadow-xl hover:shadow-emerald-500/10 transform hover:-translate-y-1"
              disabled
            >
              <div className="w-12 h-12 bg-gradient-to-r from-emerald-500 to-emerald-600 rounded-xl flex items-center justify-center mb-4 group-hover:scale-110 transition-transform duration-300">
                <span className="text-white text-xl">❓</span>
              </div>
              <h4 className="font-semibold text-slate-800 dark:text-white mb-2 group-hover:text-emerald-600 dark:group-hover:text-emerald-400 transition-colors duration-300">
                View FAQ
              </h4>
              <p className="text-sm text-slate-600 dark:text-slate-300">
                Find quick answers to common questions about features, billing, and setup.
              </p>
            </button>
          </div>
          
          {/* Trust Indicators */}
          <div className="mt-10 pt-8 border-t border-slate-200/50 dark:border-slate-600/50">
            <div className="grid grid-cols-2 md:grid-cols-4 gap-6">
              <div className="text-center">
                <div className="text-2xl font-bold text-slate-800 dark:text-white mb-1">99.9%</div>
                <div className="text-sm text-slate-600 dark:text-slate-400">Uptime SLA</div>
              </div>
              <div className="text-center">
                <div className="text-2xl font-bold text-slate-800 dark:text-white mb-1">24/7</div>
                <div className="text-sm text-slate-600 dark:text-slate-400">Support</div>
              </div>
              <div className="text-center">
                <div className="text-2xl font-bold text-slate-800 dark:text-white mb-1">30-day</div>
                <div className="text-sm text-slate-600 dark:text-slate-400">Money back</div>
              </div>
              <div className="text-center">
                <div className="text-2xl font-bold text-slate-800 dark:text-white mb-1">SOC 2</div>
                <div className="text-sm text-slate-600 dark:text-slate-400">Compliant</div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Modern Footer */}
      <footer className="bg-gradient-to-r from-slate-900 via-slate-800 to-slate-900 text-white">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          {/* Main Footer Content */}
          <div className="py-16 border-b border-slate-700/50">
            <div className="grid lg:grid-cols-4 md:grid-cols-2 gap-8">
              {/* Company Info */}
              <div className="lg:col-span-1">
                <div className="flex items-center space-x-3 mb-6">
                  <div className="w-10 h-10 rounded-xl flex items-center justify-center" style={{ background: 'linear-gradient(135deg, #3b82f6, #8b5cf6)' }}>
                    <span className="text-white font-bold text-lg">P</span>
                  </div>
                  <div>
                    <h3 className="text-xl font-bold bg-gradient-to-r from-white to-slate-200 bg-clip-text text-transparent">
                      Powernode
                    </h3>
                    <p className="text-xs text-slate-400 font-medium">Subscription Platform</p>
                  </div>
                </div>
                <p className="text-slate-300 text-sm leading-relaxed mb-6">
                  Powerful subscription management platform designed to help businesses grow. 
                  Trusted by thousands of companies worldwide.
                </p>
                <div className="flex space-x-4">
                  <button className="w-10 h-10 bg-slate-800 hover:bg-slate-700 rounded-xl flex items-center justify-center transition-colors duration-200" title="Social Media" disabled>
                    <span className="text-lg">🐦</span>
                  </button>
                  <button className="w-10 h-10 bg-slate-800 hover:bg-slate-700 rounded-xl flex items-center justify-center transition-colors duration-200" title="LinkedIn" disabled>
                    <span className="text-lg">💼</span>
                  </button>
                  <button className="w-10 h-10 bg-slate-800 hover:bg-slate-700 rounded-xl flex items-center justify-center transition-colors duration-200" title="Contact" disabled>
                    <span className="text-lg">📧</span>
                  </button>
                </div>
              </div>

              {/* Product Links */}
              <div>
                <h4 className="text-white font-semibold mb-6">Product</h4>
                <ul className="space-y-4">
                  <li>
                    <Link to="/plans" className="text-slate-300 hover:text-white transition-colors duration-200 text-sm">
                      Features
                    </Link>
                  </li>
                  <li>
                    <Link to="/plans" className="text-slate-300 hover:text-white transition-colors duration-200 text-sm">
                      Pricing
                    </Link>
                  </li>
                  <li>
                    <button className="text-slate-300 hover:text-white transition-colors duration-200 text-sm" disabled>
                      Integrations
                    </button>
                  </li>
                  <li>
                    <button className="text-slate-300 hover:text-white transition-colors duration-200 text-sm" disabled>
                      API Documentation
                    </button>
                  </li>
                  <li>
                    <button className="text-slate-300 hover:text-white transition-colors duration-200 text-sm" disabled>
                      Security
                    </button>
                  </li>
                </ul>
              </div>

              {/* Support Links */}
              <div>
                <h4 className="text-white font-semibold mb-6">Support</h4>
                <ul className="space-y-4">
                  <li>
                    <button className="text-slate-300 hover:text-white transition-colors duration-200 text-sm" disabled>
                      Help Center
                    </button>
                  </li>
                  <li>
                    <button className="text-slate-300 hover:text-white transition-colors duration-200 text-sm" disabled>
                      Contact Us
                    </button>
                  </li>
                  <li>
                    <button className="text-slate-300 hover:text-white transition-colors duration-200 text-sm" disabled>
                      System Status
                    </button>
                  </li>
                  <li>
                    <button className="text-slate-300 hover:text-white transition-colors duration-200 text-sm" disabled>
                      Community
                    </button>
                  </li>
                  <li>
                    <button className="text-slate-300 hover:text-white transition-colors duration-200 text-sm" disabled>
                      Changelog
                    </button>
                  </li>
                </ul>
              </div>

              {/* Company Links */}
              <div>
                <h4 className="text-white font-semibold mb-6">Company</h4>
                <ul className="space-y-4">
                  <li>
                    <button className="text-slate-300 hover:text-white transition-colors duration-200 text-sm" disabled>
                      About Us
                    </button>
                  </li>
                  <li>
                    <button className="text-slate-300 hover:text-white transition-colors duration-200 text-sm" disabled>
                      Careers
                    </button>
                  </li>
                  <li>
                    <button className="text-slate-300 hover:text-white transition-colors duration-200 text-sm" disabled>
                      Press
                    </button>
                  </li>
                  <li>
                    <button className="text-slate-300 hover:text-white transition-colors duration-200 text-sm" disabled>
                      Partners
                    </button>
                  </li>
                  <li>
                    <button className="text-slate-300 hover:text-white transition-colors duration-200 text-sm" disabled>
                      Blog
                    </button>
                  </li>
                </ul>
              </div>
            </div>
          </div>

          {/* Footer Bottom */}
          <div className="py-8">
            <div className="flex flex-col lg:flex-row items-center justify-between gap-6">
              <div className="flex flex-wrap items-center gap-6 text-sm text-slate-400">
                <span>© 2024 Powernode. All rights reserved.</span>
                <div className="flex items-center space-x-6">
                  <button className="hover:text-slate-300 transition-colors duration-200" disabled>
                    Privacy Policy
                  </button>
                  <button className="hover:text-slate-300 transition-colors duration-200" disabled>
                    Terms of Service
                  </button>
                  <button className="hover:text-slate-300 transition-colors duration-200" disabled>
                    Cookie Policy
                  </button>
                </div>
              </div>
              
              <div className="flex items-center space-x-6">
                <div className="flex items-center space-x-2 bg-slate-800/50 px-3 py-2 rounded-full">
                  <div className="w-2 h-2 bg-green-400 rounded-full animate-pulse"></div>
                  <span className="text-xs text-slate-300 font-medium">All systems operational</span>
                </div>
                <div className="flex items-center space-x-2 text-xs text-slate-400">
                  <ShieldCheckIcon className="h-4 w-4" />
                  <span>SOC 2 Compliant</span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </footer>

      {/* Modern Comparison Modal */}
      {showComparison && (
        <div className="fixed inset-0 bg-black/60 backdrop-blur-sm flex items-center justify-center p-4 z-50 animate-in fade-in duration-300">
          <div className="bg-white dark:bg-slate-800 rounded-2xl shadow-2xl max-w-6xl w-full max-h-[90vh] overflow-hidden border border-slate-200/50 dark:border-slate-600/50 animate-in slide-in-from-bottom-4 duration-300">
            {/* Modern Modal Header */}
            <div className="px-8 py-6 border-b border-slate-200/50 dark:border-slate-600/50 bg-gradient-to-r from-slate-50 to-blue-50/30 dark:from-slate-700/50 dark:to-slate-600/50">
              <div className="flex items-center justify-between">
                <div>
                  <h3 className="text-2xl font-bold text-slate-800 dark:text-white">Compare Plans</h3>
                  <p className="text-sm text-slate-600 dark:text-slate-400 mt-1">Side-by-side feature comparison</p>
                </div>
                <button
                  onClick={() => setShowComparison(false)}
                  className="w-10 h-10 rounded-xl bg-white dark:bg-slate-700 border border-slate-200 dark:border-slate-600 flex items-center justify-center text-slate-500 hover:text-slate-700 dark:text-slate-400 dark:hover:text-slate-200 transition-all duration-200 hover:shadow-md"
                >
                  <XMarkIcon className="h-5 w-5" />
                </button>
              </div>
            </div>

            {/* Comparison Content */}
            <div className="overflow-auto max-h-[calc(90vh-80px)]">
              <div className="p-6">
                <div className="overflow-x-auto">
                  <table className="w-full">
                    <thead>
                      <tr>
                        <th className="text-left py-3 px-4 font-medium text-slate-800 dark:text-white w-1/4">Features</th>
                        {plansToCompare.map(planId => {
                          const plan = availablePlans.find(p => p.id === planId);
                          if (!plan) return null;
                          return (
                            <th key={planId} className="text-center py-3 px-4 w-1/4">
                              <div className="space-y-2">
                                <div className="font-semibold text-slate-800 dark:text-white">{plan.name}</div>
                                <div className="text-2xl font-bold text-theme-info dark:text-blue-400">
                                  {calculatePlanPrice(plan, billingCycle)}
                                </div>
                                <div className="text-sm text-slate-600 dark:text-slate-400">
                                  per {billingCycle === 'yearly' ? 'year' : 'month'}
                                </div>
                                <button
                                  onClick={() => {
                                    setShowComparison(false);
                                    navigate(`/register?plan=${planId}&billing=${billingCycle}`);
                                  }}
                                  className="w-full bg-theme-info-solid hover:bg-theme-interactive-primary-hover text-white font-semibold px-4 py-2 rounded-lg transition-colors duration-200 text-sm"
                                >
                                  Select Plan
                                </button>
                              </div>
                            </th>
                          );
                        })}
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-slate-200 dark:divide-slate-600">
                      {/* Pricing Row */}
                      <tr className="bg-slate-50 dark:bg-slate-700">
                        <td className="py-3 px-4 font-medium text-slate-800 dark:text-white">Pricing</td>
                        {plansToCompare.map(planId => {
                          const plan = availablePlans.find(p => p.id === planId);
                          if (!plan) return null;
                          return (
                            <td key={planId} className="text-center py-3 px-4">
                              <div className="text-lg font-semibold text-slate-800 dark:text-white">
                                {calculatePlanPrice(plan, billingCycle)}
                              </div>
                              {billingCycle === 'yearly' && plan.price_cents > 0 && (
                                <div className="text-xs text-slate-600 dark:text-slate-400">
                                  {getMonthlyPrice(plan)}/month
                                </div>
                              )}
                            </td>
                          );
                        })}
                      </tr>

                      {/* Trial Period Row */}
                      <tr className="bg-white dark:bg-slate-800">
                        <td className="py-4 px-4 font-bold text-slate-800 dark:text-white">Free Trial</td>
                        {plansToCompare.map(planId => {
                          const plan = availablePlans.find(p => p.id === planId);
                          if (!plan) return null;
                          return (
                            <td key={planId} className="text-center py-4 px-4">
                              {(plan.trial_days && plan.trial_days > 0) ? (
                                <div className="inline-flex items-center justify-center px-3 py-1.5 bg-green-100 text-green-800 rounded-full border border-green-200 font-semibold text-sm">
                                  🎁 {plan.trial_days} days free
                                </div>
                              ) : (
                                <div className="inline-flex items-center justify-center px-3 py-1.5 bg-theme-surface text-theme-muted rounded-full border border-theme font-medium text-sm">
                                  No trial
                                </div>
                              )}
                            </td>
                          );
                        })}
                      </tr>

                      {/* Features Rows */}
                      {getAllPlanFeatures().map((feature, index) => (
                        <tr key={index} className={`${index % 2 === 0 ? 'bg-slate-50 dark:bg-slate-700' : 'bg-white dark:bg-slate-800'} hover:bg-slate-100 dark:hover:bg-slate-600`}>
                          <td className="py-3 px-4 font-medium text-slate-800 dark:text-white">{feature}</td>
                          {plansToCompare.map(planId => {
                            const plan = availablePlans.find(p => p.id === planId);
                            if (!plan) return null;
                            const hasFeature = planHasFeature(plan, feature);
                            return (
                              <td key={planId} className="text-center py-3 px-4">
                                {hasFeature ? (
                                  <CheckIcon className="h-5 w-5 text-theme-success mx-auto" />
                                ) : (
                                  <span className="text-slate-400 dark:text-slate-500">—</span>
                                )}
                              </td>
                            );
                          })}
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </div>
            </div>

            {/* Modern Modal Footer */}
            <div className="px-8 py-6 border-t border-slate-200/50 dark:border-slate-600/50 bg-gradient-to-r from-slate-50 to-blue-50/30 dark:from-slate-700/50 dark:to-slate-600/50">
              <div className="flex flex-col sm:flex-row items-center justify-between gap-4">
                <div className="text-center sm:text-left">
                  <p className="text-sm font-medium text-slate-700 dark:text-slate-300">
                    Select a plan to continue with your registration
                  </p>
                  <p className="text-xs text-slate-500 dark:text-slate-400">
                    Compare features and pricing across different plans
                  </p>
                </div>
                <button
                  onClick={() => setShowComparison(false)}
                  className="inline-flex items-center space-x-2 px-6 py-3 bg-slate-100 hover:bg-slate-200 dark:bg-slate-600 dark:hover:bg-slate-500 text-slate-700 dark:text-slate-200 font-medium rounded-xl transition-all duration-200 transform hover:scale-105"
                >
                  <span>Close Comparison</span>
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

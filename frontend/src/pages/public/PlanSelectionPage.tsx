import React, { useState, useEffect } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { plansApi, Plan } from '@/features/business/plans/services/plansApi';
import {
  CheckIcon,
  ShieldCheckIcon,
  ClockIcon,
  ScaleIcon,
  ArrowRightIcon
} from '@heroicons/react/24/outline';
import { PlanCard } from '@/features/business/plans/components/PlanCard';
import { AnnualSavingsCalculator } from '@/features/business/plans/components/AnnualSavingsCalculator';
import {
  PlanComparisonModal,
  PublicFooter,
  PlanStickyCta,
  calculatePlanPrice,
  getMonthlyPrice,
  isPlanPopular,
  getAllPlanFeatures,
  planHasFeature
} from '@/features/business/plans/components/plan-selection';


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
        const { plans } = response.data;
        setAvailablePlans(plans);
        // Auto-select the first plan or a featured plan
        if (plans.length > 0) {
          const featuredPlan = plans.find((plan) => plan.name.toLowerCase().includes('pro') || plan.name.toLowerCase().includes('standard'));
          setSelectedPlanId(featuredPlan?.id || plans[0].id);
        }
      }
    } catch (error: unknown) {
    } finally {
      setPlansLoading(false);
    }
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
                  className="inline-flex items-center space-x-2 px-4 py-2.5 bg-theme-success-solid hover:opacity-90 text-white text-sm font-semibold rounded-lg transition-all duration-200 transform hover:scale-105 shadow-lg hover:shadow-xl"
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
          <div className="absolute top-40 left-10 w-72 h-72 bg-theme-info/5 rounded-full blur-3xl"></div>
          <div className="absolute top-20 right-20 w-96 h-96 bg-theme-interactive-primary/5 rounded-full blur-3xl"></div>
          <div className="absolute bottom-20 left-1/2 w-80 h-80 bg-theme-info/5 rounded-full blur-3xl transform -translate-x-1/2"></div>
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
              <div className="w-8 h-8 bg-theme-success/20 rounded-full flex items-center justify-center">
                <ShieldCheckIcon className="h-4 w-4 text-theme-success" />
              </div>
              <span className="text-sm font-semibold" style={{color: 'var(--public-text-primary)'}}>30-day money back</span>
            </div>
            
            <div className="flex items-center space-x-3 surface px-4 py-3 rounded-full">
              <div className="w-8 h-8 bg-theme-info/20 rounded-full flex items-center justify-center">
                <ClockIcon className="h-4 w-4 text-theme-info" />
              </div>
              <span className="text-sm font-semibold" style={{color: 'var(--public-text-primary)'}}>Free trial included</span>
            </div>
            
            <div className="flex items-center space-x-3 surface px-4 py-3 rounded-full">
              <div className="w-8 h-8 bg-theme-interactive-primary/20 rounded-full flex items-center justify-center">
                <CheckIcon className="h-4 w-4 text-theme-interactive-primary" />
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
                  data-testid="billing-monthly"
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
                  data-testid="billing-yearly"
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
              <div className="inline-flex items-center space-x-2 bg-theme-success/10 px-4 py-3 rounded-full border border-theme-success/30">
                <div className="w-6 h-6 bg-theme-success rounded-full flex items-center justify-center animate-pulse">
                  <span className="text-white text-sm">💰</span>
                </div>
                <p className="text-sm font-semibold text-theme-success">
                  You're saving money with annual billing!
                </p>
              </div>
            </div>
          )}
          
          {/* Comparison Helper */}
          {plansToCompare.length > 0 && (
            <div className="text-center bg-white/50 dark:bg-slate-800/50 backdrop-blur-sm px-6 py-4 rounded-xl border border-slate-200/50 dark:border-slate-600/50">
              <div className="flex items-center justify-center space-x-3 mb-2">
                <div className="w-2 h-2 bg-theme-info-solid rounded-full animate-pulse"></div>
                <p className="text-sm font-medium text-slate-700 dark:text-slate-300">
                  {plansToCompare.length} plan{plansToCompare.length > 1 ? 's' : ''} selected for comparison
                </p>
              </div>
              {plansToCompare.length >= 2 ? (
                <button
                  onClick={() => startComparison?.()}
                  className="inline-flex items-center space-x-2 text-sm font-semibold text-theme-info hover:text-theme-info/80 transition-colors duration-200"
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

      {/* Sticky CTA Section */}
      <PlanStickyCta
        selectedPlan={getSelectedPlan()}
        billingCycle={billingCycle}
        calculatePlanPrice={calculatePlanPrice}
        onContinue={handleContinue}
      />

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
              className="group bg-white/80 dark:bg-slate-700/50 backdrop-blur-sm rounded-2xl p-6 border border-slate-200/50 dark:border-slate-600/50 hover:border-theme-info transition-all duration-300 hover:shadow-xl hover:shadow-theme-info/10 transform hover:-translate-y-1"
              disabled
            >
              <div className="w-12 h-12 bg-gradient-to-r from-blue-500 to-blue-600 rounded-xl flex items-center justify-center mb-4 group-hover:scale-110 transition-transform duration-300">
                <span className="text-white text-xl">📧</span>
              </div>
              <h4 className="font-semibold text-slate-800 dark:text-white mb-2 group-hover:text-theme-info transition-colors duration-300">
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
              className="group bg-white/80 dark:bg-slate-700/50 backdrop-blur-sm rounded-2xl p-6 border border-slate-200/50 dark:border-slate-600/50 hover:border-theme-interactive-primary transition-all duration-300 hover:shadow-xl hover:shadow-theme-interactive-primary/10 transform hover:-translate-y-1 text-left"
            >
              <div className="w-12 h-12 bg-gradient-to-r from-purple-500 to-purple-600 rounded-xl flex items-center justify-center mb-4 group-hover:scale-110 transition-transform duration-300">
                <ScaleIcon className="h-6 w-6 text-white" />
              </div>
              <h4 className="font-semibold text-slate-800 dark:text-white mb-2 group-hover:text-theme-interactive-primary transition-colors duration-300">
                Compare Plans
              </h4>
              <p className="text-sm text-slate-600 dark:text-slate-300">
                See a detailed side-by-side comparison of features and pricing across all plans.
              </p>
            </button>
            
            <button 
              className="group bg-white/80 dark:bg-slate-700/50 backdrop-blur-sm rounded-2xl p-6 border border-slate-200/50 dark:border-slate-600/50 hover:border-theme-success transition-all duration-300 hover:shadow-xl hover:shadow-theme-success/10 transform hover:-translate-y-1"
              disabled
            >
              <div className="w-12 h-12 bg-gradient-to-r from-emerald-500 to-emerald-600 rounded-xl flex items-center justify-center mb-4 group-hover:scale-110 transition-transform duration-300">
                <span className="text-white text-xl">❓</span>
              </div>
              <h4 className="font-semibold text-slate-800 dark:text-white mb-2 group-hover:text-theme-success transition-colors duration-300">
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

      {/* Footer */}
      <PublicFooter />

      {/* Comparison Modal */}
      <PlanComparisonModal
        isOpen={showComparison}
        onClose={() => setShowComparison(false)}
        plansToCompare={plansToCompare}
        availablePlans={availablePlans}
        billingCycle={billingCycle}
        calculatePlanPrice={calculatePlanPrice}
        getMonthlyPrice={(plan) => getMonthlyPrice(plan, billingCycle)}
        getAllPlanFeatures={() => getAllPlanFeatures(availablePlans)}
        planHasFeature={planHasFeature}
      />
    </div>
  );
};

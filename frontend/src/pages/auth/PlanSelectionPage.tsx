import React, { useState, useEffect } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { plansApi, Plan } from '../../services/plansApi';
import { 
  CheckIcon, 
  SparklesIcon,
  ArrowRightIcon,
  StarIcon,
  ShieldCheckIcon,
  ClockIcon,
  ScaleIcon,
  XMarkIcon
} from '@heroicons/react/24/outline';
import { StarIcon as StarSolidIcon } from '@heroicons/react/24/solid';

export const PlanSelectionPage: React.FC = () => {
  const navigate = useNavigate();
  const [availablePlans, setAvailablePlans] = useState<Plan[]>([]);
  const [plansLoading, setPlansLoading] = useState(false);
  const [selectedPlanId, setSelectedPlanId] = useState<string | null>(null);
  const [billingCycle, setBillingCycle] = useState<'monthly' | 'yearly'>('monthly');
  const [showComparison, setShowComparison] = useState(false);
  const [plansToCompare, setPlansToCompare] = useState<string[]>([]);

  useEffect(() => {
    loadAvailablePlans();
  }, []);

  const loadAvailablePlans = async () => {
    try {
      setPlansLoading(true);
      const response = await plansApi.getPublicPlans();
      if (response.success) {
        setAvailablePlans(response.data.plans);
        // Auto-select the first plan or a featured plan
        if (response.data.plans.length > 0) {
          const featuredPlan = response.data.plans.find(plan => plan.name.toLowerCase().includes('pro') || plan.name.toLowerCase().includes('standard'));
          setSelectedPlanId(featuredPlan?.id || response.data.plans[0].id);
        }
      }
    } catch (error) {
      console.error('Failed to load plans:', error);
    } finally {
      setPlansLoading(false);
    }
  };

  const calculatePlanPrice = (plan: Plan, cycle: 'monthly' | 'yearly'): string => {
    if (plan.price_cents === 0) return 'Free';
    
    let priceCents = plan.price_cents;
    
    // If plan is yearly and user wants monthly, or vice versa, convert
    if (cycle === 'yearly' && plan.billing_cycle === 'monthly') {
      priceCents = priceCents * 12 * 0.8; // 20% discount for annual
    } else if (cycle === 'monthly' && plan.billing_cycle === 'yearly') {
      priceCents = priceCents / 12;
    }
    
    const amount = priceCents / 100;
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: plan.currency
    }).format(amount);
  };

  const getMonthlyPrice = (plan: Plan): string => {
    if (plan.price_cents === 0) return 'Free';
    
    let monthlyCents = plan.price_cents;
    if (plan.billing_cycle === 'yearly') {
      monthlyCents = monthlyCents / 12;
    }
    
    const amount = monthlyCents / 100;
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: plan.currency
    }).format(amount);
  };

  const handlePlanSelection = (planId: string) => {
    setSelectedPlanId(planId);
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
    // Mock features based on plan tier - in real app this would come from the API
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
    <div className="min-h-screen bg-theme-background-secondary">
      {/* Header */}
      <div className="bg-theme-surface shadow-sm">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
          <div className="flex items-center justify-between">
            <div className="flex items-center space-x-4">
              <div className="w-10 h-10 bg-theme-interactive-primary rounded-xl flex items-center justify-center">
                <span className="text-white font-bold text-lg">P</span>
              </div>
              <div>
                <h1 className="text-2xl font-bold text-theme-primary">Powernode</h1>
                <p className="text-sm text-theme-secondary">Choose your plan</p>
              </div>
            </div>
            <div className="flex items-center space-x-4">
              {plansToCompare.length >= 2 && (
                <button
                  onClick={startComparison}
                  className="inline-flex items-center space-x-2 px-4 py-2 bg-theme-success text-white text-sm font-medium rounded-lg hover:bg-theme-success transition-colors opacity-90 hover:opacity-100"
                >
                  <ScaleIcon className="h-4 w-4" />
                  <span>Compare {plansToCompare.length} Plans</span>
                </button>
              )}
              <Link
                to="/login"
                className="text-sm font-medium text-theme-link hover:text-theme-link-hover"
              >
                Already have an account?
              </Link>
            </div>
          </div>
        </div>
      </div>

      {/* Hero Section */}
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-16">
        <div className="text-center mb-16">
          <h2 className="text-4xl font-bold text-theme-primary mb-4">
            Choose the perfect plan for your needs
          </h2>
          <p className="text-xl text-theme-secondary max-w-2xl mx-auto">
            Start your journey with Powernode. All plans include our core features with different levels of scale and support.
          </p>
          
          {/* Trust Indicators */}
          <div className="flex items-center justify-center space-x-8 mt-8 text-sm text-theme-secondary">
            <div className="flex items-center space-x-2">
              <ShieldCheckIcon className="h-5 w-5 text-theme-success" />
              <span>30-day money back guarantee</span>
            </div>
            <div className="flex items-center space-x-2">
              <ClockIcon className="h-5 w-5 text-theme-info" />
              <span>14-day free trial</span>
            </div>
            <div className="flex items-center space-x-2">
              <CheckIcon className="h-5 w-5 text-theme-success" />
              <span>No setup fees</span>
            </div>
          </div>
        </div>

        {/* Billing Toggle */}
        <div className="flex flex-col items-center mb-12">
          <div className="bg-theme-surface rounded-lg p-1 shadow-sm border border-theme flex mb-4">
            <button
              onClick={() => setBillingCycle('monthly')}
              className={`px-6 py-3 text-sm font-medium rounded-md transition-colors ${
                billingCycle === 'monthly'
                  ? 'bg-theme-interactive-primary text-white shadow-sm'
                  : 'text-theme-secondary hover:text-theme-primary'
              }`}
            >
              Monthly billing
            </button>
            <button
              onClick={() => setBillingCycle('yearly')}
              className={`px-6 py-3 text-sm font-medium rounded-md transition-colors relative ${
                billingCycle === 'yearly'
                  ? 'bg-theme-interactive-primary text-white shadow-sm'
                  : 'text-theme-secondary hover:text-theme-primary'
              }`}
            >
              Annual billing
              <span className="ml-2 inline-flex items-center px-2 py-1 rounded-full text-xs bg-theme-success text-theme-success opacity-90">
                Save 20%
              </span>
            </button>
          </div>
          
          {/* Comparison Helper */}
          {plansToCompare.length > 0 && (
            <div className="text-center">
              <p className="text-sm text-theme-secondary mb-2">
                {plansToCompare.length} plan{plansToCompare.length > 1 ? 's' : ''} selected for comparison
                {plansToCompare.length >= 2 && (
                  <button
                    onClick={startComparison}
                    className="ml-2 text-theme-success hover:text-theme-success font-medium opacity-80 hover:opacity-100"
                  >
                    Compare now →
                  </button>
                )}
              </p>
              {plansToCompare.length < 2 && (
                <p className="text-xs text-theme-tertiary">
                  Select at least 2 plans to compare features
                </p>
              )}
            </div>
          )}
        </div>

        {/* Plans Grid */}
        <div className="grid md:grid-cols-3 gap-8 max-w-5xl mx-auto">
          {availablePlans.map((plan) => (
            <div
              key={plan.id}
              onClick={() => handlePlanSelection(plan.id)}
              className={`relative cursor-pointer card-theme rounded-xl border-2 transition-all hover:shadow-lg ${
                selectedPlanId === plan.id
                  ? 'border-theme-focus shadow-lg scale-105'
                  : 'border-theme hover:border-theme-focus'
              } ${isPlanPopular(plan) ? 'ring-2 ring-theme-focus ring-opacity-20' : ''}`}
            >
              {/* Popular Badge */}
              {isPlanPopular(plan) && (
                <div className="absolute -top-4 left-1/2 transform -translate-x-1/2">
                  <div className="bg-theme-interactive-primary text-white px-4 py-1 rounded-full text-sm font-medium flex items-center space-x-1">
                    <StarSolidIcon className="h-4 w-4" />
                    <span>Most Popular</span>
                  </div>
                </div>
              )}

              {/* Selection Indicator */}
              {selectedPlanId === plan.id && (
                <div className="absolute top-4 right-4">
                  <div className="w-6 h-6 bg-theme-interactive-primary rounded-full flex items-center justify-center">
                    <CheckIcon className="h-4 w-4 text-white" />
                  </div>
                </div>
              )}

              {/* Compare Checkbox */}
              <div className="absolute top-4 left-4">
                <label className="flex items-center space-x-2 cursor-pointer">
                  <input
                    type="checkbox"
                    checked={plansToCompare.includes(plan.id)}
                    onChange={(e) => {
                      e.stopPropagation();
                      togglePlanComparison(plan.id);
                    }}
                    disabled={!plansToCompare.includes(plan.id) && plansToCompare.length >= 3}
                    className="w-4 h-4 text-theme-success border-theme rounded focus:ring-theme-success"
                  />
                  <span className="text-xs text-theme-tertiary">Compare</span>
                </label>
              </div>

              <div className="p-8">
                {/* Plan Header */}
                <div className="text-center mb-6">
                  <h3 className="text-xl font-bold text-theme-primary mb-2">{plan.name}</h3>
                  {plan.description && (
                    <p className="text-theme-secondary text-sm mb-4">{plan.description}</p>
                  )}
                  
                  {/* Pricing */}
                  <div className="mb-4">
                    <div className="text-4xl font-bold text-theme-primary">
                      {calculatePlanPrice(plan, billingCycle)}
                    </div>
                    <div className="text-sm text-theme-secondary">
                      per {billingCycle === 'yearly' ? 'year' : 'month'}
                    </div>
                    {billingCycle === 'yearly' && plan.price_cents > 0 && (
                      <div className="text-xs text-theme-tertiary mt-1">
                        {getMonthlyPrice(plan)}/month billed annually
                      </div>
                    )}
                  </div>

                  {/* Trial Info */}
                  {plan.trial_days > 0 && (
                    <div className="text-sm text-theme-info font-medium mb-4">
                      {plan.trial_days} day free trial
                    </div>
                  )}
                </div>

                {/* Features */}
                <ul className="space-y-3 mb-8">
                  {getPlanFeatures(plan).map((feature, index) => (
                    <li key={index} className="flex items-start space-x-3">
                      <CheckIcon className="h-5 w-5 text-theme-success flex-shrink-0 mt-0.5" />
                      <span className="text-sm text-theme-secondary">{feature}</span>
                    </li>
                  ))}
                </ul>

                {/* Plan CTA */}
                <div className="text-center">
                  {selectedPlanId === plan.id ? (
                    <div className="w-full bg-theme-interactive-primary text-white py-3 px-4 rounded-lg font-medium flex items-center justify-center space-x-2">
                      <CheckIcon className="h-5 w-5" />
                      <span>Selected</span>
                    </div>
                  ) : (
                    <div className="w-full border-2 border-theme text-theme-secondary py-3 px-4 rounded-lg font-medium hover:border-theme-focus hover:bg-theme-background-secondary transition-colors">
                      Select {plan.name}
                    </div>
                  )}
                </div>
              </div>
            </div>
          ))}
        </div>

        {/* Selected Plan Summary & CTA */}
        {selectedPlanId && (
          <div className="mt-16 max-w-2xl mx-auto">
            <div className="card-theme rounded-xl shadow-lg p-8">
              <div className="text-center mb-6">
                <h3 className="text-lg font-semibold text-theme-primary mb-2">
                  Ready to get started with {getSelectedPlan()?.name}?
                </h3>
                <p className="text-theme-secondary">
                  You'll be able to review and modify your subscription after creating your account.
                </p>
              </div>
              
              <div className="flex items-center justify-between p-4 bg-theme-background-secondary rounded-lg mb-6">
                <div>
                  <div className="font-medium text-theme-primary">{getSelectedPlan()?.name}</div>
                  <div className="text-sm text-theme-secondary">
                    Billed {billingCycle}
                    {getSelectedPlan()?.trial_days && getSelectedPlan()!.trial_days > 0 && (
                      <span className="ml-2 text-theme-info">• {getSelectedPlan()!.trial_days} day trial</span>
                    )}
                  </div>
                </div>
                <div className="text-right">
                  <div className="text-xl font-bold text-theme-primary">
                    {calculatePlanPrice(getSelectedPlan()!, billingCycle)}
                  </div>
                  <div className="text-sm text-theme-secondary">
                    per {billingCycle === 'yearly' ? 'year' : 'month'}
                  </div>
                </div>
              </div>

              <button
                onClick={handleContinue}
                className="w-full bg-theme-interactive-primary hover:bg-theme-interactive-primary-hover text-white font-semibold py-4 px-6 rounded-lg transition-colors flex items-center justify-center space-x-2"
              >
                <span>Continue to Registration</span>
                <ArrowRightIcon className="h-5 w-5" />
              </button>
              
              <p className="text-xs text-theme-tertiary text-center mt-4">
                No credit card required • Cancel anytime • 30-day money-back guarantee
              </p>
            </div>
          </div>
        )}

        {/* FAQ/Additional Info */}
        <div className="mt-20 text-center">
          <h3 className="text-lg font-medium text-theme-primary mb-4">
            Questions? We're here to help
          </h3>
          <div className="flex items-center justify-center space-x-8 text-sm">
            <a href="mailto:support@powernode.com" className="text-theme-link hover:text-theme-link-hover">
              Contact Support
            </a>
            <button 
              onClick={() => {
                // Auto-select all plans for comparison if none selected
                if (plansToCompare.length === 0) {
                  setPlansToCompare(availablePlans.map(plan => plan.id).slice(0, 3));
                }
                setShowComparison(true);
              }}
              className="text-theme-link hover:text-theme-link-hover"
            >
              Compare Plans
            </button>
            <a href="/faq" className="text-theme-link hover:text-theme-link-hover">
              View FAQ
            </a>
          </div>
        </div>
      </div>

      {/* Comparison Modal */}
      {showComparison && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center p-4 z-50">
          <div className="card-theme rounded-xl shadow-xl max-w-6xl w-full max-h-[90vh] overflow-hidden">
            {/* Modal Header */}
            <div className="px-6 py-4 border-b border-theme flex items-center justify-between">
              <h3 className="text-xl font-semibold text-theme-primary">Compare Plans</h3>
              <button
                onClick={() => setShowComparison(false)}
                className="text-theme-tertiary hover:text-theme-secondary transition-colors"
              >
                <XMarkIcon className="h-6 w-6" />
              </button>
            </div>

            {/* Comparison Content */}
            <div className="overflow-auto max-h-[calc(90vh-80px)]">
              <div className="p-6">
                <div className="overflow-x-auto">
                  <table className="w-full">
                    <thead>
                      <tr>
                        <th className="text-left py-3 px-4 font-medium text-theme-primary w-1/4">Features</th>
                        {plansToCompare.map(planId => {
                          const plan = availablePlans.find(p => p.id === planId);
                          if (!plan) return null;
                          return (
                            <th key={planId} className="text-center py-3 px-4 w-1/4">
                              <div className="space-y-2">
                                <div className="font-semibold text-theme-primary">{plan.name}</div>
                                <div className="text-2xl font-bold text-theme-interactive-primary">
                                  {calculatePlanPrice(plan, billingCycle)}
                                </div>
                                <div className="text-sm text-theme-secondary">
                                  per {billingCycle === 'yearly' ? 'year' : 'month'}
                                </div>
                                <button
                                  onClick={() => {
                                    handlePlanSelection(planId);
                                    setShowComparison(false);
                                  }}
                                  className="btn-theme btn-theme-primary w-full text-sm"
                                >
                                  Select Plan
                                </button>
                              </div>
                            </th>
                          );
                        })}
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-theme">
                      {/* Pricing Row */}
                      <tr className="bg-theme-background-secondary">
                        <td className="py-3 px-4 font-medium text-theme-primary">Pricing</td>
                        {plansToCompare.map(planId => {
                          const plan = availablePlans.find(p => p.id === planId);
                          if (!plan) return null;
                          return (
                            <td key={planId} className="text-center py-3 px-4">
                              <div className="text-lg font-semibold text-theme-primary">
                                {calculatePlanPrice(plan, billingCycle)}
                              </div>
                              {billingCycle === 'yearly' && plan.price_cents > 0 && (
                                <div className="text-xs text-theme-secondary">
                                  {getMonthlyPrice(plan)}/month
                                </div>
                              )}
                            </td>
                          );
                        })}
                      </tr>

                      {/* Trial Period Row */}
                      <tr>
                        <td className="py-3 px-4 font-medium text-theme-primary">Free Trial</td>
                        {plansToCompare.map(planId => {
                          const plan = availablePlans.find(p => p.id === planId);
                          if (!plan) return null;
                          return (
                            <td key={planId} className="text-center py-3 px-4">
                              {plan.trial_days > 0 ? (
                                <span className="text-theme-success font-medium">
                                  {plan.trial_days} days
                                </span>
                              ) : (
                                <span className="text-theme-tertiary">No trial</span>
                              )}
                            </td>
                          );
                        })}
                      </tr>

                      {/* Features Rows */}
                      {getAllPlanFeatures().map((feature, index) => (
                        <tr key={index} className={`${index % 2 === 0 ? 'bg-theme-background-secondary hover:bg-theme-background-secondary' : 'bg-theme-background hover:bg-theme-background'}`}>
                          <td className="py-3 px-4 font-medium text-theme-primary">{feature}</td>
                          {plansToCompare.map(planId => {
                            const plan = availablePlans.find(p => p.id === planId);
                            if (!plan) return null;
                            const hasFeature = planHasFeature(plan, feature);
                            return (
                              <td key={planId} className="text-center py-3 px-4">
                                {hasFeature ? (
                                  <CheckIcon className="h-5 w-5 text-theme-success mx-auto" />
                                ) : (
                                  <span className="text-theme-tertiary">—</span>
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

            {/* Modal Footer */}
            <div className="px-6 py-4 border-t border-theme bg-theme-background-secondary">
              <div className="flex items-center justify-between">
                <p className="text-sm text-theme-secondary">
                  Select a plan to continue with your registration
                </p>
                <button
                  onClick={() => setShowComparison(false)}
                  className="btn-theme btn-theme-secondary px-4 py-2 text-sm"
                >
                  Close Comparison
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
import React, { useState, useEffect } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { plansApi, Plan } from '../../services/plansApi';
import { 
  CheckIcon, 
  SparklesIcon,
  ArrowRightIcon,
  StarIcon,
  ShieldCheckIcon,
  ClockIcon
} from '@heroicons/react/24/outline';
import { StarIcon as StarSolidIcon } from '@heroicons/react/24/solid';

export const PlanSelectionPage: React.FC = () => {
  const navigate = useNavigate();
  const [availablePlans, setAvailablePlans] = useState<Plan[]>([]);
  const [plansLoading, setPlansLoading] = useState(false);
  const [selectedPlanId, setSelectedPlanId] = useState<string | null>(null);
  const [billingCycle, setBillingCycle] = useState<'monthly' | 'yearly'>('monthly');

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

  if (plansLoading) {
    return (
      <div className="min-h-screen bg-gray-50 flex items-center justify-center">
        <div className="text-center">
          <div className="animate-spin h-12 w-12 border-4 border-blue-600 border-t-transparent rounded-full mx-auto mb-4"></div>
          <p className="text-gray-600">Loading plans...</p>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Header */}
      <div className="bg-white shadow-sm">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
          <div className="flex items-center justify-between">
            <div className="flex items-center space-x-4">
              <div className="w-10 h-10 bg-blue-600 rounded-xl flex items-center justify-center">
                <span className="text-white font-bold text-lg">P</span>
              </div>
              <div>
                <h1 className="text-2xl font-bold text-gray-900">Powernode</h1>
                <p className="text-sm text-gray-500">Choose your plan</p>
              </div>
            </div>
            <Link
              to="/login"
              className="text-sm font-medium text-blue-600 hover:text-blue-500"
            >
              Already have an account?
            </Link>
          </div>
        </div>
      </div>

      {/* Hero Section */}
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-16">
        <div className="text-center mb-16">
          <h2 className="text-4xl font-bold text-gray-900 mb-4">
            Choose the perfect plan for your needs
          </h2>
          <p className="text-xl text-gray-600 max-w-2xl mx-auto">
            Start your journey with Powernode. All plans include our core features with different levels of scale and support.
          </p>
          
          {/* Trust Indicators */}
          <div className="flex items-center justify-center space-x-8 mt-8 text-sm text-gray-500">
            <div className="flex items-center space-x-2">
              <ShieldCheckIcon className="h-5 w-5 text-green-500" />
              <span>30-day money back guarantee</span>
            </div>
            <div className="flex items-center space-x-2">
              <ClockIcon className="h-5 w-5 text-blue-500" />
              <span>14-day free trial</span>
            </div>
            <div className="flex items-center space-x-2">
              <CheckIcon className="h-5 w-5 text-green-500" />
              <span>No setup fees</span>
            </div>
          </div>
        </div>

        {/* Billing Toggle */}
        <div className="flex justify-center mb-12">
          <div className="bg-white rounded-lg p-1 shadow-sm border flex">
            <button
              onClick={() => setBillingCycle('monthly')}
              className={`px-6 py-3 text-sm font-medium rounded-md transition-colors ${
                billingCycle === 'monthly'
                  ? 'bg-blue-600 text-white shadow-sm'
                  : 'text-gray-600 hover:text-gray-900'
              }`}
            >
              Monthly billing
            </button>
            <button
              onClick={() => setBillingCycle('yearly')}
              className={`px-6 py-3 text-sm font-medium rounded-md transition-colors relative ${
                billingCycle === 'yearly'
                  ? 'bg-blue-600 text-white shadow-sm'
                  : 'text-gray-600 hover:text-gray-900'
              }`}
            >
              Annual billing
              <span className="ml-2 inline-flex items-center px-2 py-1 rounded-full text-xs bg-green-100 text-green-800">
                Save 20%
              </span>
            </button>
          </div>
        </div>

        {/* Plans Grid */}
        <div className="grid md:grid-cols-3 gap-8 max-w-5xl mx-auto">
          {availablePlans.map((plan) => (
            <div
              key={plan.id}
              onClick={() => handlePlanSelection(plan.id)}
              className={`relative cursor-pointer bg-white rounded-xl border-2 transition-all hover:shadow-lg ${
                selectedPlanId === plan.id
                  ? 'border-blue-500 shadow-lg scale-105'
                  : 'border-gray-200 hover:border-gray-300'
              } ${isPlanPopular(plan) ? 'ring-2 ring-blue-500 ring-opacity-20' : ''}`}
            >
              {/* Popular Badge */}
              {isPlanPopular(plan) && (
                <div className="absolute -top-4 left-1/2 transform -translate-x-1/2">
                  <div className="bg-blue-600 text-white px-4 py-1 rounded-full text-sm font-medium flex items-center space-x-1">
                    <StarSolidIcon className="h-4 w-4" />
                    <span>Most Popular</span>
                  </div>
                </div>
              )}

              {/* Selection Indicator */}
              {selectedPlanId === plan.id && (
                <div className="absolute top-4 right-4">
                  <div className="w-6 h-6 bg-blue-600 rounded-full flex items-center justify-center">
                    <CheckIcon className="h-4 w-4 text-white" />
                  </div>
                </div>
              )}

              <div className="p-8">
                {/* Plan Header */}
                <div className="text-center mb-6">
                  <h3 className="text-xl font-bold text-gray-900 mb-2">{plan.name}</h3>
                  {plan.description && (
                    <p className="text-gray-600 text-sm mb-4">{plan.description}</p>
                  )}
                  
                  {/* Pricing */}
                  <div className="mb-4">
                    <div className="text-4xl font-bold text-gray-900">
                      {calculatePlanPrice(plan, billingCycle)}
                    </div>
                    <div className="text-sm text-gray-500">
                      per {billingCycle === 'yearly' ? 'year' : 'month'}
                    </div>
                    {billingCycle === 'yearly' && plan.price_cents > 0 && (
                      <div className="text-xs text-gray-400 mt-1">
                        {getMonthlyPrice(plan)}/month billed annually
                      </div>
                    )}
                  </div>

                  {/* Trial Info */}
                  {plan.trial_days > 0 && (
                    <div className="text-sm text-blue-600 font-medium mb-4">
                      {plan.trial_days} day free trial
                    </div>
                  )}
                </div>

                {/* Features */}
                <ul className="space-y-3 mb-8">
                  {getPlanFeatures(plan).map((feature, index) => (
                    <li key={index} className="flex items-start space-x-3">
                      <CheckIcon className="h-5 w-5 text-green-500 flex-shrink-0 mt-0.5" />
                      <span className="text-sm text-gray-600">{feature}</span>
                    </li>
                  ))}
                </ul>

                {/* Plan CTA */}
                <div className="text-center">
                  {selectedPlanId === plan.id ? (
                    <div className="w-full bg-blue-600 text-white py-3 px-4 rounded-lg font-medium flex items-center justify-center space-x-2">
                      <CheckIcon className="h-5 w-5" />
                      <span>Selected</span>
                    </div>
                  ) : (
                    <div className="w-full border-2 border-gray-200 text-gray-600 py-3 px-4 rounded-lg font-medium hover:border-gray-300 hover:bg-gray-50 transition-colors">
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
            <div className="bg-white rounded-xl shadow-lg border p-8">
              <div className="text-center mb-6">
                <h3 className="text-lg font-semibold text-gray-900 mb-2">
                  Ready to get started with {getSelectedPlan()?.name}?
                </h3>
                <p className="text-gray-600">
                  You'll be able to review and modify your subscription after creating your account.
                </p>
              </div>
              
              <div className="flex items-center justify-between p-4 bg-gray-50 rounded-lg mb-6">
                <div>
                  <div className="font-medium text-gray-900">{getSelectedPlan()?.name}</div>
                  <div className="text-sm text-gray-500">
                    Billed {billingCycle}
                    {getSelectedPlan()?.trial_days && getSelectedPlan()!.trial_days > 0 && (
                      <span className="ml-2 text-blue-600">• {getSelectedPlan()!.trial_days} day trial</span>
                    )}
                  </div>
                </div>
                <div className="text-right">
                  <div className="text-xl font-bold text-gray-900">
                    {calculatePlanPrice(getSelectedPlan()!, billingCycle)}
                  </div>
                  <div className="text-sm text-gray-500">
                    per {billingCycle === 'yearly' ? 'year' : 'month'}
                  </div>
                </div>
              </div>

              <button
                onClick={handleContinue}
                className="w-full bg-blue-600 hover:bg-blue-700 text-white font-semibold py-4 px-6 rounded-lg transition-colors flex items-center justify-center space-x-2"
              >
                <span>Continue to Registration</span>
                <ArrowRightIcon className="h-5 w-5" />
              </button>
              
              <p className="text-xs text-gray-500 text-center mt-4">
                No credit card required • Cancel anytime • 30-day money-back guarantee
              </p>
            </div>
          </div>
        )}

        {/* FAQ/Additional Info */}
        <div className="mt-20 text-center">
          <h3 className="text-lg font-medium text-gray-900 mb-4">
            Questions? We're here to help
          </h3>
          <div className="flex items-center justify-center space-x-8 text-sm">
            <a href="mailto:support@powernode.com" className="text-blue-600 hover:text-blue-500">
              Contact Support
            </a>
            <a href="/pricing" className="text-blue-600 hover:text-blue-500">
              Compare Plans
            </a>
            <a href="/faq" className="text-blue-600 hover:text-blue-500">
              View FAQ
            </a>
          </div>
        </div>
      </div>
    </div>
  );
};
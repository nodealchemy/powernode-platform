import React, { useState, useEffect, useCallback } from 'react';

import { Link, useNavigate, useSearchParams } from 'react-router-dom';

import { useDispatch, useSelector } from 'react-redux';

import { RootState, AppDispatch } from '@/shared/services';

import { register, clearError } from '@/shared/services/slices/authSlice';

import { addNotification } from '@/shared/services/slices/uiSlice';

import { plansApi, Plan } from '@/features/plans/services/plansApi';

import { getErrorMessage } from '@/shared/utils/errorHandling';

import {
  EyeIcon, 
  EyeSlashIcon,
  ArrowLeftIcon,
  CheckIcon
} from '@heroicons/react/24/outline';

interface RegistrationData {
  // Personal info
  name: string;
  email: string;
  password: string;
  // Company info
  accountName: string;
}

export const RegisterPage: React.FC = () => {
  const dispatch = useDispatch<AppDispatch>();
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  
  const { isLoading, error } = useSelector((state: RootState) => state.auth);
  
  const [showPassword, setShowPassword] = useState(false);
  const [selectedPlan, setSelectedPlan] = useState<Plan | null>(null);
  const [billingCycle, setBillingCycle] = useState<'monthly' | 'yearly'>('monthly');
  
  // Form data - initialize with preserved state if available
  const [formData, setFormData] = useState<RegistrationData>(() => {
    // Check if there's preserved form data in sessionStorage
    const preservedData = sessionStorage.getItem('registrationFormData');
    if (preservedData) {
      try {
        const parsed = JSON.parse(preservedData);
        return {
          ...parsed,
          email: searchParams.get('email') || parsed.email, // Prefer URL email param
          password: '' // Never preserve password
        };
      } catch {
        // Fall through to default if parsing fails
      }
    }
    
    return {
      name: '',
      email: searchParams.get('email') || '',
      password: '',
      accountName: ''
    };
  });

  const loadSelectedPlan = useCallback(async (planId: string) => {
    try {
      // Use public plans endpoint since user is not authenticated
      const response = await plansApi.getPublicPlans();
      if (response.success) {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const plan = (response.data as any).plans.find((p: any) => p.id === planId);
        if (plan) {
          setSelectedPlan(plan);
        } else {
          navigate('/plans');
        }
      }
    } catch (error: unknown) {
      // Redirect back to plan selection if plan loading fails
      navigate('/plans');
    }
  }, [navigate]);

  // Load selected plan from URL params
  useEffect(() => {

    const planId = searchParams.get('plan');
    const billing = searchParams.get('billing') as 'monthly' | 'yearly' || 'monthly';
    
    if (planId) {
      loadSelectedPlan(planId);
      setBillingCycle(billing);
    } else {
      // Redirect to plan selection if no plan is selected
      navigate('/plans');
    }
  }, [searchParams, navigate, loadSelectedPlan]);

  // Clear error when component unmounts
  useEffect(() => {

    return () => {
      if (error) {
        dispatch(clearError());
      }
    };
  }, [dispatch, error]);

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const { name, value } = e.target;
    const updatedFormData = { ...formData, [name]: value };
    setFormData(updatedFormData);
    
    // Preserve form data in sessionStorage (except password)
    const { password: _, ...dataToPreserve } = updatedFormData;
    sessionStorage.setItem('registrationFormData', JSON.stringify(dataToPreserve));
    
    if (error) {
      dispatch(clearError());
    }
  };

  const validateForm = (): boolean => {
    return !!(
      formData.name.trim() &&
      formData.email.trim() &&
      formData.password.length >= 8 &&
      formData.accountName.trim() &&
      selectedPlan
    );
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    e.stopPropagation();
    
    if (!validateForm() || !selectedPlan) return;
    
    try {
      const registrationPayload = {
        email: formData.email,
        password: formData.password,
        name: formData.name,
        account_name: formData.accountName,
        plan_id: selectedPlan.id,
        billing_cycle: billingCycle
      };

      await dispatch(register(registrationPayload)).unwrap();

      // Clear preserved form data on successful registration
      sessionStorage.removeItem('registrationFormData');
      
      dispatch(addNotification({
        type: 'success',
        message: 'Registration successful! Welcome to Powernode.',
      }));
      navigate('/dashboard', { replace: true });
    } catch (error: unknown) {
      const errorMessage = getErrorMessage(error);
      dispatch(addNotification({
        type: 'error',
        message: errorMessage,
      }));
      
      // Prevent any potential page refresh by stopping event propagation
      e.preventDefault();
    }
  };

  const calculatePlanPrice = (plan: Plan, billingCycle: 'monthly' | 'yearly'): string => {
    if (plan.price_cents === 0) return 'Free';
    
    let priceCents = plan.price_cents;
    
    // If plan is yearly and user wants monthly, or vice versa, convert
    if (billingCycle === 'yearly' && plan.billing_cycle === 'monthly') {
      priceCents = priceCents * 12 * 0.8; // 20% discount for annual
    } else if (billingCycle === 'monthly' && plan.billing_cycle === 'yearly') {
      priceCents = priceCents / 12;
    }
    
    const amount = priceCents / 100;
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: plan.currency
    }).format(amount);
  };

  return (
    <div className="min-h-screen bg-theme-background-secondary flex flex-col justify-center py-12 px-4 sm:px-6 lg:px-8">
      <div className="sm:mx-auto sm:w-full sm:max-w-md">
        {/* Logo and Title */}
        <div className="text-center">
          <Link to="/welcome" className="inline-block">
            <div className="mx-auto w-16 h-16 bg-theme-interactive-primary rounded-2xl flex items-center justify-center mb-6 shadow-lg hover:shadow-xl transition-all duration-200 hover:scale-105">
              <span className="text-white font-bold text-2xl">P</span>
            </div>
          </Link>
          <h1 className="text-3xl font-bold text-theme-primary mb-2">Powernode</h1>
          <p className="text-theme-secondary">Create your account</p>
        </div>
      </div>

      <div className="mt-8 sm:mx-auto sm:w-full sm:max-w-md">
        <div className="bg-theme-surface py-8 px-4 shadow-xl border border-theme sm:rounded-xl sm:px-10">

          {error && (
            <div className="mb-6 bg-theme-error border border-theme text-theme-error px-4 py-3 rounded-lg">
              <div className="flex">
                <div className="ml-3">
                  <p className="text-sm font-medium">{error}</p>
                </div>
              </div>
            </div>
          )}

          {/* Back to Plan Selection */}
          <div className="mb-6">
            <Link
              to="/plans"
              className="inline-flex items-center space-x-2 text-sm text-theme-link hover:text-theme-link-hover transition-colors"
            >
              <ArrowLeftIcon className="h-4 w-4" />
              <span>Change plan</span>
            </Link>
          </div>

          {/* Selected Plan Summary */}
          {selectedPlan && (
            <div className="mb-6 p-4 bg-theme-info border border-theme rounded-lg">
              <div className="flex items-center justify-between">
                <div className="flex items-center space-x-3">
                  <div className="w-6 h-6 bg-theme-interactive-primary rounded-full flex items-center justify-center">
                    <CheckIcon className="h-4 w-4 text-white" />
                  </div>
                  <div>
                    <h4 className="font-medium text-theme-primary">{selectedPlan.name}</h4>
                    <p className="text-sm text-theme-secondary">
                      Billed {billingCycle}
                      {selectedPlan.trial_days > 0 && (
                        <span className="ml-2 text-theme-info">• {selectedPlan.trial_days} day trial</span>
                      )}
                    </p>
                  </div>
                </div>
                <div className="text-right">
                  <div className="font-semibold text-theme-primary">
                    {calculatePlanPrice(selectedPlan, billingCycle)}
                  </div>
                  <div className="text-sm text-theme-secondary">
                    per {billingCycle === 'yearly' ? 'year' : 'month'}
                  </div>
                </div>
              </div>
            </div>
          )}

          <form className="space-y-6" onSubmit={handleSubmit}>

            {/* Company Information */}
            <div className="space-y-4">
              <h3 className="text-lg font-semibold text-theme-primary">Company Information</h3>
              <div>
                <label htmlFor="accountName" className="label-theme">
                  Company Name
                </label>
                <input
                  id="accountName"
                  name="accountName"
                  type="text"
                  required
                  className="input-theme"
                  placeholder="Enter company name"
                  value={formData.accountName}
                  onChange={(e) => void handleChange(e)}
                />
              </div>
            </div>

            {/* Personal Information */}
            <div className="space-y-4">
              <h3 className="text-lg font-semibold text-theme-primary">Your Account</h3>
              <div>
                <label htmlFor="name" className="label-theme">
                  Full Name
                </label>
                <input
                  id="name"
                  name="name"
                  type="text"
                  required
                  className="input-theme"
                  placeholder="Enter your full name"
                  value={formData.name}
                  onChange={(e) => void handleChange(e)}
                />
              </div>

              <div>
                <label htmlFor="email" className="label-theme">
                  Email Address
                </label>
                <input
                  id="email"
                  name="email"
                  type="email"
                  autoComplete="email"
                  required
                  className="input-theme"
                  placeholder="Enter your email"
                  value={formData.email}
                  onChange={(e) => void handleChange(e)}
                />
              </div>

              <div>
                <label htmlFor="password" className="label-theme">
                  Password
                </label>
                <div className="relative">
                  <input
                    id="password"
                    name="password"
                    type={showPassword ? 'text' : 'password'}
                    autoComplete="new-password"
                    required
                    className="input-theme pr-12"
                    placeholder="Create a password"
                    value={formData.password}
                    onChange={(e) => void handleChange(e)}
                  />
                  <button
                    type="button"
                    className="absolute inset-y-0 right-0 pr-3 flex items-center text-theme-tertiary hover:text-theme-secondary transition-colors"
                    onClick={() => setShowPassword(!showPassword)}
                    aria-label={showPassword ? "Hide password" : "Show password"}
                  >
                    {showPassword ? (
                      <EyeSlashIcon className="h-5 w-5" aria-hidden="true" />
                    ) : (
                      <EyeIcon className="h-5 w-5" aria-hidden="true" />
                    )}
                  </button>
                </div>
                <p className="mt-2 text-xs text-theme-tertiary">
                  Password must be at least 8 characters long
                </p>
              </div>
            </div>

            {/* Submit Button */}
            <div className="pt-4">
              <button
                type="submit"
                disabled={isLoading || !validateForm()}
                className="btn-theme btn-theme-primary w-full py-3"
                onClick={(e) => {
                  // Ensure form submission is handled properly
                  if (!validateForm() || isLoading) {
                    e.preventDefault();
                    e.stopPropagation();
                    return false;
                  }
                }}
              >
                {isLoading ? (
                  <div className="flex items-center justify-center">
                    <div className="animate-spin -ml-1 mr-3 h-5 w-5 border-2 border-white border-t-transparent rounded-full" />
                    Creating account...
                  </div>
                ) : (
                  'Create Account'
                )}
              </button>
            </div>

            {/* Sign In Link */}
            <div className="text-center pt-4 border-t border-theme">
              <p className="text-sm text-theme-secondary">
                Already have an account?{' '}
                <Link
                  to="/login"
                  className="font-medium text-theme-link hover:text-theme-link-hover transition-colors"
                >
                  Sign in
                </Link>
              </p>
            </div>
          </form>
        </div>
      </div>
    </div>
  );
};

export default RegisterPage;

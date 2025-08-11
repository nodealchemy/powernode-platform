import React, { useState, useEffect } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import { useDispatch, useSelector } from 'react-redux';
import { RootState, AppDispatch } from '../../store';
import { register, clearError } from '../../store/slices/authSlice';
import { addNotification } from '../../store/slices/uiSlice';
import { plansApi, Plan } from '../../services/plansApi';
import { 
  EyeIcon, 
  EyeSlashIcon,
  ArrowLeftIcon,
  CheckIcon
} from '@heroicons/react/24/outline';

interface RegistrationData {
  // Personal info
  firstName: string;
  lastName: string;
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
  
  // Form data
  const [formData, setFormData] = useState<RegistrationData>({
    firstName: '',
    lastName: '',
    email: searchParams.get('email') || '',
    password: '',
    accountName: ''
  });

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
  }, [searchParams, navigate]);

  // Clear error when component unmounts
  useEffect(() => {
    return () => {
      if (error) {
        dispatch(clearError());
      }
    };
  }, [dispatch]);

  const loadSelectedPlan = async (planId: string) => {
    try {
      // Use public plans endpoint since user is not authenticated
      const response = await plansApi.getPublicPlans();
      if (response.success) {
        const plan = response.data.plans.find(p => p.id === planId);
        if (plan) {
          setSelectedPlan(plan);
        } else {
          console.error('Plan not found in public plans');
          navigate('/plans');
        }
      }
    } catch (error) {
      console.error('Failed to load public plans:', error);
      // Redirect back to plan selection if plan loading fails
      navigate('/plans');
    }
  };

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const { name, value } = e.target;
    setFormData((prev) => ({ ...prev, [name]: value }));
    
    if (error) {
      dispatch(clearError());
    }
  };

  const validateForm = (): boolean => {
    return !!(
      formData.firstName.trim() && 
      formData.lastName.trim() && 
      formData.email.trim() && 
      formData.password.length >= 8 && 
      formData.accountName.trim() &&
      selectedPlan
    );
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    
    if (!validateForm() || !selectedPlan) return;
    
    try {
      const registrationPayload = {
        email: formData.email,
        password: formData.password,
        firstName: formData.firstName,
        lastName: formData.lastName,
        accountName: formData.accountName,
        planId: selectedPlan.id,
        billingCycle: billingCycle
      };
      
      await dispatch(register(registrationPayload)).unwrap();
      dispatch(addNotification({
        type: 'success',
        message: 'Registration successful! Welcome to Powernode.',
      }));
      navigate('/dashboard', { replace: true });
    } catch (error: any) {
      dispatch(addNotification({
        type: 'error',
        message: error.message || 'Registration failed. Please try again.',
      }));
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
          <div className="mx-auto w-16 h-16 bg-theme-interactive-primary rounded-2xl flex items-center justify-center mb-6 shadow-lg">
            <span className="text-white font-bold text-2xl">P</span>
          </div>
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
                  onChange={handleChange}
                />
              </div>
            </div>

            {/* Personal Information */}
            <div className="space-y-4">
              <h3 className="text-lg font-semibold text-theme-primary">Your Account</h3>
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label htmlFor="firstName" className="label-theme">
                    First Name
                  </label>
                  <input
                    id="firstName"
                    name="firstName"
                    type="text"
                    required
                    className="input-theme"
                    placeholder="First name"
                    value={formData.firstName}
                    onChange={handleChange}
                  />
                </div>
                <div>
                  <label htmlFor="lastName" className="label-theme">
                    Last Name
                  </label>
                  <input
                    id="lastName"
                    name="lastName"
                    type="text"
                    required
                    className="input-theme"
                    placeholder="Last name"
                    value={formData.lastName}
                    onChange={handleChange}
                  />
                </div>
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
                  onChange={handleChange}
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
                    onChange={handleChange}
                  />
                  <button
                    type="button"
                    className="absolute inset-y-0 right-0 pr-3 flex items-center text-theme-tertiary hover:text-theme-secondary transition-colors"
                    onClick={() => setShowPassword(!showPassword)}
                  >
                    {showPassword ? (
                      <EyeSlashIcon className="h-5 w-5" />
                    ) : (
                      <EyeIcon className="h-5 w-5" />
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

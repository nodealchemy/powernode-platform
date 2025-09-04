import React, { useState, useEffect } from 'react';
import { useSelector, useDispatch } from 'react-redux';
import { RootState, AppDispatch } from '@/shared/services';
import { fetchSubscriptions, createSubscription, updateSubscription, setAvailablePlans } from '@/shared/services/slices/subscriptionSlice';
import { CurrentPlanSummary } from './CurrentPlanSummary';
import { SimplePlanBrowser } from './SimplePlanBrowser';
import { SubscriptionModal } from './SubscriptionModal';
import { useSubscriptionWebSocket } from '@/shared/hooks/useSubscriptionWebSocket';
import { useNotification } from '@/shared/hooks/useNotification';
import { Plan, Subscription } from '../services/subscriptionService';
import { CreditCard, ExternalLink, HelpCircle, Mail, RefreshCw, TrendingUp } from 'lucide-react';

interface ProfileSubscriptionTabProps {
  loading?: boolean;
  className?: string;
}

// Mock plans data (in real app, this would come from API)
const mockPlans: Plan[] = [
  {
    id: '1',
    name: 'Starter',
    price: { cents: 999, currency_iso: 'USD' },
    billing_cycle: 'monthly',
    status: 'active',
    isPublic: true,
    features: {
      basic_support: true,
      api_access: true,
      storage_gb: '5GB'
    },
    trialDays: 14
  },
  {
    id: '2',
    name: 'Professional',
    price: { cents: 2999, currency_iso: 'USD' },
    billing_cycle: 'monthly',
    status: 'active',
    isPublic: true,
    features: {
      priority_support: true,
      api_access: true,
      advanced_analytics: true,
      storage_gb: '50GB'
    },
    trialDays: 14
  },
  {
    id: '3',
    name: 'Enterprise',
    price: { cents: 9999, currency_iso: 'USD' },
    billing_cycle: 'monthly',
    status: 'active',
    isPublic: true,
    features: {
      dedicated_support: true,
      api_access: true,
      advanced_analytics: true,
      unlimited_storage: true
    },
    trialDays: 30
  }
];

export const ProfileSubscriptionTab: React.FC<ProfileSubscriptionTabProps> = ({
  loading: propLoading = false,
  className = ''
}) => {
  const dispatch = useDispatch<AppDispatch>();
  const { showNotification } = useNotification();
  const { user } = useSelector((state: RootState) => state.auth);
  const { subscriptions, currentSubscription, availablePlans, loading: subscriptionLoading, error } = useSelector((state: RootState) => state.subscription);

  const [selectedSubscription, setSelectedSubscription] = useState<Subscription | null>(null);
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [billingCycle, setBillingCycle] = useState<'monthly' | 'yearly'>('monthly');

  const loading = propLoading || subscriptionLoading;

  // WebSocket integration for real-time updates
  useSubscriptionWebSocket({
    onSubscriptionUpdate: (data: unknown) => {
      dispatch(fetchSubscriptions());
    },
    onSubscriptionCancelled: (data: unknown) => {
      dispatch(fetchSubscriptions());
    },
    onPaymentProcessed: (data: unknown) => {
      dispatch(fetchSubscriptions());
    },
    onTrialEnding: (data: unknown) => {
      // Could show a notification here
    },
    onError: (error: string) => {
      // Handle WebSocket errors silently in profile context
    }
  });

  // Load subscription data
  useEffect(() => {
    // Set mock plans (in real app, this would be an API call)
    dispatch(setAvailablePlans(mockPlans as any));
    
    // Fetch real subscriptions
    dispatch(fetchSubscriptions());
  }, [dispatch]);

  const handlePlanSelect = async (planId: string) => {
    try {
      if (currentSubscription) {
        // Update existing subscription
        const result = await dispatch(updateSubscription({
          id: currentSubscription.id,
          data: { planId }
        }));
        
        if (updateSubscription.fulfilled.match(result)) {
          showNotification('Plan updated successfully!', 'success');
        } else {
          showNotification('Failed to update plan. Please try again.', 'error');
        }
      } else {
        // Create new subscription
        const result = await dispatch(createSubscription({ planId }));
        
        if (createSubscription.fulfilled.match(result)) {
          showNotification('Subscription created successfully!', 'success');
        } else {
          showNotification('Failed to create subscription. Please try again.', 'error');
        }
      }
    } catch (error) {
      showNotification('An error occurred. Please try again.', 'error');
    }
  };

  const handleManageSubscription = () => {
    if (currentSubscription) {
      setSelectedSubscription(currentSubscription);
      setIsModalOpen(true);
    }
  };

  const handleRefresh = () => {
    dispatch(fetchSubscriptions());
  };

  const handleBillingManagement = () => {
    // Navigate to billing management
    window.location.href = '/app/business/billing';
  };

  // Check if user has billing permissions
  const canViewBilling = user?.permissions?.includes('billing.read') || user?.permissions?.includes('billing.manage');
  const canManageBilling = user?.permissions?.includes('billing.manage');

  if (!canViewBilling) {
    return (
      <div className={`text-center py-8 ${className}`}>
        <div className="mx-auto w-16 h-16 rounded-full flex items-center justify-center mb-4 bg-theme-secondary">
          <CreditCard className="h-8 w-8 text-theme-primary" />
        </div>
        <h3 className="text-lg font-medium text-theme-primary mb-2">Access Restricted</h3>
        <p className="text-sm text-theme-secondary mb-4">
          You don't have permission to view billing information.
        </p>
        <p className="text-xs text-theme-secondary">
          Contact your administrator to request billing access.
        </p>
      </div>
    );
  }

  return (
    <div className={`space-y-8 ${className}`}>
      {/* Error Display */}
      {error && (
        <div className="alert-theme alert-theme-error">
          <span className="block sm:inline">{error}</span>
          <button 
            onClick={handleRefresh}
            className="ml-2 text-sm underline hover:no-underline"
          >
            Try again
          </button>
        </div>
      )}

      {/* Section 1: Current Plan Summary */}
      <CurrentPlanSummary
        subscription={currentSubscription}
        loading={loading}
        onManage={canManageBilling ? handleManageSubscription : undefined}
      />

      {/* Section 2: Quick Actions */}
      {canManageBilling && (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {/* Upgrade/Plan Management */}
          <div className="card-theme p-6">
            <div className="flex items-center space-x-3 mb-3">
              <TrendingUp className="h-5 w-5 text-theme-link" />
              <h3 className="font-semibold text-theme-primary">Plan Management</h3>
            </div>
            <p className="text-sm text-theme-secondary mb-4">
              {currentSubscription 
                ? 'Upgrade, downgrade, or modify your current plan.'
                : 'Choose a plan to get started with premium features.'
              }
            </p>
            <button
              onClick={handleManageSubscription}
              disabled={!currentSubscription}
              className="btn-theme btn-theme-secondary w-full"
            >
              {currentSubscription ? 'Change Plan' : 'Select Plan'}
            </button>
          </div>

          {/* Billing Management */}
          <div className="card-theme p-6">
            <div className="flex items-center space-x-3 mb-3">
              <CreditCard className="h-5 w-5 text-theme-link" />
              <h3 className="font-semibold text-theme-primary">Billing & Payment</h3>
            </div>
            <p className="text-sm text-theme-secondary mb-4">
              Manage payment methods, view invoices, and update billing information.
            </p>
            <button
              onClick={handleBillingManagement}
              className="btn-theme btn-theme-secondary w-full flex items-center justify-center space-x-2"
            >
              <span>Manage Billing</span>
              <ExternalLink className="h-4 w-4" />
            </button>
          </div>
        </div>
      )}

      {/* Section 3: Available Plans */}
      {canManageBilling && (
        <div className="card-theme shadow">
          <div className="px-6 py-4 border-b border-theme">
            <div className="flex justify-between items-center">
              <div>
                <h3 className="text-lg font-medium text-theme-primary">Available Plans</h3>
                <p className="text-sm text-theme-secondary mt-1">
                  {currentSubscription 
                    ? 'Compare plans and upgrade or downgrade as needed'
                    : 'Choose the plan that best fits your needs'
                  }
                </p>
              </div>
              <button
                onClick={handleRefresh}
                disabled={loading}
                className="btn-theme btn-theme-ghost p-2"
                title="Refresh plans"
              >
                <RefreshCw className={`h-4 w-4 ${loading ? 'animate-spin' : ''}`} />
              </button>
            </div>
          </div>
          <div className="p-6">
            <SimplePlanBrowser
              plans={availablePlans as Plan[]}
              currentSubscription={currentSubscription}
              onPlanSelect={handlePlanSelect}
              loading={loading}
              billingCycle={billingCycle}
              onBillingCycleChange={setBillingCycle}
            />
          </div>
        </div>
      )}

      {/* Section 4: Help & Support */}
      <div className="card-theme p-6">
        <div className="flex items-center space-x-3 mb-3">
          <HelpCircle className="h-5 w-5 text-theme-secondary" />
          <h3 className="font-medium text-theme-primary">Need Help?</h3>
        </div>
        <p className="text-sm text-theme-secondary mb-4">
          Have questions about your subscription or need assistance with billing?
        </p>
        <div className="flex flex-col sm:flex-row space-y-2 sm:space-y-0 sm:space-x-3">
          <button
            onClick={() => window.location.href = '/support'}
            className="btn-theme btn-theme-ghost flex items-center justify-center space-x-2"
          >
            <HelpCircle className="h-4 w-4" />
            <span>View Help Center</span>
          </button>
          <button
            onClick={() => window.location.href = 'mailto:support@powernode.com'}
            className="btn-theme btn-theme-ghost flex items-center justify-center space-x-2"
          >
            <Mail className="h-4 w-4" />
            <span>Contact Support</span>
          </button>
        </div>
      </div>

      {/* Subscription Management Modal */}
      <SubscriptionModal
        isOpen={isModalOpen}
        onClose={() => setIsModalOpen(false)}
        subscription={selectedSubscription}
        availablePlans={availablePlans}
        onUpgrade={handlePlanSelect}
        onCancel={async (subscriptionId: string) => {
          // Handle cancellation - would typically call API
          showNotification('Subscription cancellation processed.', 'success');
          setIsModalOpen(false);
          dispatch(fetchSubscriptions());
        }}
        loading={loading}
      />
    </div>
  );
};
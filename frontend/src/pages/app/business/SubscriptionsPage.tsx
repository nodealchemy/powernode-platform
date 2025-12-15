import React, { useEffect, useState } from 'react';
import { useSelector, useDispatch } from 'react-redux';
import { RootState, AppDispatch } from '@/shared/services';
import { fetchSubscriptions, createSubscription, updateSubscription, cancelSubscription, setAvailablePlans } from '@/shared/services/slices/subscriptionSlice';
import { SubscriptionPlanCard } from '@/features/subscriptions/components/SubscriptionPlanCard';
import { SubscriptionModal } from '@/features/subscriptions/components/SubscriptionModal';
import { SubscriptionStatusIndicator } from '@/features/subscriptions/components/SubscriptionStatusIndicator';
import { useSubscriptionLifecycle } from '@/shared/hooks/useSubscriptionLifecycle';
import { useSubscriptionWebSocket } from '@/shared/hooks/useSubscriptionWebSocket';
import { useNotification } from '@/shared/hooks/useNotification';
import { Plan } from '@/features/plans/services/plansApi';
import { Subscription } from '@/shared/types';
import { subscriptionHistoryApi, SubscriptionHistoryResponse } from '@/shared/services/subscriptionHistoryApi';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { RefreshCw, CreditCard } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';

// Mock plans data with proper Plan interface structure
const mockPlans: Plan[] = [
  {
    id: '1',
    name: 'Starter',
    description: 'Perfect for small teams getting started',
    price_cents: 999,
    currency: 'USD',
    billing_cycle: 'monthly',
    status: 'active',
    trial_days: 14,
    is_public: true,
    formatted_price: '$9.99',
    monthly_price: '$9.99',
    features: {
      basic_support: true,
      api_access: true
    },
    limits: {
      users: 5,
      projects: 10,
      storage: 5
    },
    has_annual_discount: true,
    annual_discount_percent: 10,
    has_promotional_discount: false,
    promotional_discount_percent: 0,
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString()
  },
  {
    id: '2',
    name: 'Professional',
    description: 'For growing teams with advanced needs',
    price_cents: 2999,
    currency: 'USD',
    billing_cycle: 'monthly',
    status: 'active',
    trial_days: 14,
    is_public: true,
    formatted_price: '$29.99',
    monthly_price: '$29.99',
    features: {
      priority_support: true,
      api_access: true,
      advanced_analytics: true
    },
    limits: {
      users: 25,
      projects: 100,
      storage: 50
    },
    has_annual_discount: true,
    annual_discount_percent: 20,
    has_promotional_discount: true,
    promotional_discount_percent: 15,
    promotional_discount_start: new Date().toISOString(),
    promotional_discount_end: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(),
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString()
  },
  {
    id: '3',
    name: 'Enterprise',
    description: 'For large organizations with complex requirements',
    price_cents: 9999,
    currency: 'USD',
    billing_cycle: 'monthly',
    status: 'active',
    trial_days: 30,
    is_public: true,
    formatted_price: '$99.99',
    monthly_price: '$99.99',
    features: {
      dedicated_support: true,
      api_access: true,
      advanced_analytics: true
    },
    limits: {
      users: -1,
      projects: -1,
      storage: 500
    },
    has_annual_discount: true,
    annual_discount_percent: 15,
    has_volume_discount: true,
    volume_discount_tiers: [
      { min_quantity: 10, discount_percent: 5 },
      { min_quantity: 25, discount_percent: 10 },
      { min_quantity: 50, discount_percent: 15 }
    ],
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString()
  },
  {
    id: '4',
    name: 'Administrator',
    description: 'Administrative access plan',
    price_cents: 0,
    currency: 'USD',
    billing_cycle: 'monthly',
    status: 'active',
    trial_days: 0,
    is_public: false,
    formatted_price: 'Free',
    monthly_price: 'Free',
    features: {
      api_access: true,
      advanced_analytics: true
    },
    limits: {
      users: -1,
      projects: -1,
      storage: -1
    },
    has_annual_discount: false,
    annual_discount_percent: 0,
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString()
  }
];

export const SubscriptionsPage: React.FC = () => {
  const dispatch = useDispatch<AppDispatch>();
  const { showNotification } = useNotification();
  const { subscriptions, currentSubscription, availablePlans, loading, error } = useSelector((state: RootState) => state.subscription);
  const [selectedSubscription, setSelectedSubscription] = useState<Subscription | null>(null);
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [subscriptionHistory, setSubscriptionHistory] = useState<SubscriptionHistoryResponse | null>(null);
  const [historyLoading, setHistoryLoading] = useState(false);
  const [showAllHistory, setShowAllHistory] = useState(false);
  const [billingCycle, setBillingCycle] = useState<'monthly' | 'yearly'>('monthly');

  // Use lifecycle management and real-time updates
  const { checkSubscriptionStatus, getDaysUntilExpiry } = useSubscriptionLifecycle();
  useSubscriptionWebSocket({
    onSubscriptionUpdate: (_data) => {
      // Refresh subscriptions when updates are received
      dispatch(fetchSubscriptions());
    },
    onSubscriptionCancelled: (_data) => {
      dispatch(fetchSubscriptions());
    },
    onPaymentProcessed: (_data) => {
      dispatch(fetchSubscriptions());
    },
    onTrialEnding: (data) => {
      const trialData = data as { plan_name?: string } | undefined;
      showNotification(
        `Your trial for ${trialData?.plan_name || 'your subscription'} is ending soon. Upgrade now to continue using all features.`,
        'warning'
      );
    },
    onError: (error) => {
      console.error('Subscription WebSocket error:', error);
    }
  }); // Maintain realtime updates without displaying status

  const loadSubscriptionHistory = async () => {
    try {
      setHistoryLoading(true);
      const historyData = await subscriptionHistoryApi.getHistory();
      setSubscriptionHistory(historyData);
    } catch (error) {
      console.error('Failed to load subscription history:', error);
    } finally {
      setHistoryLoading(false);
    }
  };

  useEffect(() => {
    // Set mock plans (in real app, this would be an API call)
    dispatch(setAvailablePlans(mockPlans as any));
    
    // Fetch real subscriptions
    dispatch(fetchSubscriptions());
    
    // Load subscription history
    loadSubscriptionHistory();
  }, [dispatch]);

  const handleSubscribe = async (planId: string) => {
    try {
      const result = await dispatch(createSubscription({ plan_id: planId }));
      if (createSubscription.fulfilled.match(result)) {
        showNotification('Subscription created successfully!', 'success');
      } else {
        showNotification('Failed to create subscription. Please try again.', 'error');
      }
    } catch (error) {
      showNotification('An error occurred. Please try again.', 'error');
    }
  };

  const handleManagePlan = (planId: string) => {
    const subscription = subscriptions.find(sub => sub.plan.id === planId);
    if (subscription) {
      setSelectedSubscription(subscription);
      setIsModalOpen(true);
    }
  };

  const handleUpgrade = async (planId: string) => {
    if (selectedSubscription) {
      try {
        const result = await dispatch(updateSubscription({
          id: selectedSubscription.id,
          data: { plan_id: planId }
        }));
        if (updateSubscription.fulfilled.match(result)) {
          showNotification('Subscription upgraded successfully!', 'success');
          setIsModalOpen(false);
        } else {
          showNotification('Failed to upgrade subscription. Please try again.', 'error');
        }
      } catch (error) {
        showNotification('An error occurred. Please try again.', 'error');
      }
    }
  };

  const handleCancel = async (subscriptionId: string) => {
    try {
      const result = await dispatch(cancelSubscription(subscriptionId));
      if (cancelSubscription.fulfilled.match(result)) {
        showNotification('Subscription cancelled successfully.', 'success');
        setIsModalOpen(false);
      } else {
        showNotification('Failed to cancel subscription. Please try again.', 'error');
      }
    } catch (error) {
      showNotification('An error occurred. Please try again.', 'error');
    }
  };

  const getSubscriptionForPlan = (planId: string): Subscription | undefined => {
    return subscriptions.find(sub => sub.plan.id === planId && sub.status === 'active');
  };

  const formatDate = (dateString: string | null | undefined) => {
    if (!dateString) return 'No expiration';
    
    const date = new Date(dateString);
    if (isNaN(date.getTime())) return 'No expiration';
    
    return date.toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'long',
      day: 'numeric',
    });
  };



  const pageActions: PageAction[] = [
    {
      id: 'refresh',
      label: 'Refresh',
      onClick: () => dispatch(fetchSubscriptions()),
      variant: 'secondary',
      icon: RefreshCw,
      disabled: loading
    },
    {
      id: 'manage-billing',
      label: 'Manage Billing',
      onClick: () => window.location.href = '/app/business/billing',
      variant: 'primary',
      icon: CreditCard
    }
  ];

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app', icon: '🏠' },
    { label: 'Subscriptions', icon: '📋' }
  ];

  return (
    <PageContainer
      title="Subscriptions"
      description="Manage your subscription plans and billing settings."
      breadcrumbs={breadcrumbs}
      actions={pageActions}
    >
      <div className="space-y-6">
        {/* Error Display */}
        {error && (
          <div className="alert-theme alert-theme-error">
            <span className="block sm:inline">{error}</span>
          </div>
        )}

        {/* Current Subscription Summary */}
        {currentSubscription && (
          <div className="card-theme shadow p-6">
            <h3 className="text-lg font-medium text-theme-primary mb-4">Current Subscription</h3>
            <div className="grid grid-cols-1 md:grid-cols-4 gap-6 items-start">
              <div>
                <p className="text-sm text-theme-secondary">Plan</p>
                <p className="text-lg font-medium text-theme-primary">{currentSubscription.plan.name}</p>
                <p className="text-sm text-theme-secondary">{currentSubscription.plan.formatted_price}/{currentSubscription.plan.billing_cycle}</p>
              </div>
              <div>
                <p className="text-sm text-theme-secondary mb-2">Status</p>
                <SubscriptionStatusIndicator 
                  subscription={currentSubscription} 
                  showDetails={false}
                />
              </div>
              <div>
                <p className="text-sm text-theme-secondary">
                  {currentSubscription.current_period_end ? 'Next Billing' : 'Billing'}
                </p>
                <p className="text-lg font-medium text-theme-primary">{formatDate(currentSubscription.current_period_end)}</p>
                <p className="text-sm text-theme-secondary">
                  {currentSubscription.current_period_end ? (
                    `${getDaysUntilExpiry(currentSubscription)} days remaining`
                  ) : (
                    'Never expires'
                  )}
                </p>
              </div>
              <div>
                <Button
                  onClick={() => {
                    setSelectedSubscription(currentSubscription);
                    setIsModalOpen(true);
                  }}variant="primary"
                >
                  Manage Subscription
                </Button>
              </div>
            </div>
            
            {/* Enhanced status details for critical states */}
            {(checkSubscriptionStatus(currentSubscription) === 'trial_ending' || 
              checkSubscriptionStatus(currentSubscription) === 'expiring') && (
              <div className="mt-4">
                <SubscriptionStatusIndicator 
                  subscription={currentSubscription} 
                  showDetails={true}
                />
              </div>
            )}
          </div>
        )}

        {/* Available Plans */}
        <div className="card-theme shadow">
          <div className="px-6 py-4 border-b border-theme">
            <div className="flex justify-between items-center">
              <div>
                <h3 className="text-lg font-medium text-theme-primary">Available Plans</h3>
                <p className="text-sm text-theme-secondary mt-1">Choose a plan that best fits your needs</p>
              </div>
              {/* Billing Cycle Toggle */}
              <div className="flex bg-theme-surface rounded-lg p-1 shadow-sm border border-theme">
                <Button
                  onClick={() => setBillingCycle('monthly')}
                  variant={billingCycle === 'monthly' ? 'primary' : 'ghost'}
                  size="sm"
                  className={billingCycle === 'monthly' ? '' : 'text-theme-secondary'}
                >
                  Monthly
                </Button>
                <Button
                  onClick={() => setBillingCycle('yearly')}
                  variant={billingCycle === 'yearly' ? 'primary' : 'ghost'}
                  size="sm"
                  className={billingCycle === 'yearly' ? '' : 'text-theme-secondary'}
                >
                  Yearly
                  <span className="ml-1 text-xs text-theme-success">Save up to 20%</span>
                </Button>
              </div>
            </div>
          </div>
          <div className="p-6">
            {loading ? (
              <div className="flex items-center justify-center py-8">
                <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-theme-link"></div>
                <span className="ml-2 text-theme-secondary">Loading plans...</span>
              </div>
            ) : (
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
                {(availablePlans as any[]).filter((plan: any) => plan.is_public).map((plan: any) => {
                  const subscription = getSubscriptionForPlan(plan.id);
                  const isActive = !!subscription;
                  
                  // Determine if this plan offers the best value (highest discount or middle tier)
                  const planDiscount = billingCycle === 'yearly' && plan.has_annual_discount 
                    ? (plan.annual_discount_percent || 0)
                    : (plan.has_promotional_discount ? (plan.promotional_discount_percent || 0) : 0);
                  
                  const allDiscounts = (availablePlans as any[]).filter((p: any) => p.is_public).map((p: any) => {
                    if (billingCycle === 'yearly' && p.has_annual_discount) {
                      return p.annual_discount_percent || 0;
                    }
                    return p.has_promotional_discount ? (p.promotional_discount_percent || 0) : 0;
                  });
                  
                  const maxDiscount = Math.max(...allDiscounts.map(d => parseFloat(d.toString())));
                  const isBestValue = parseFloat(planDiscount.toString()) === maxDiscount && maxDiscount > 0;
                  
                  // Mark middle tier as popular (usually Professional/Standard plans)
                  const isPopular = plan.name.toLowerCase().includes('pro') || 
                                   plan.name.toLowerCase().includes('standard') ||
                                   plan.name.toLowerCase().includes('professional');
                  
                  return (
                    <SubscriptionPlanCard
                      key={plan.id}
                      plan={plan}
                      isActive={isActive}
                      onSubscribe={!subscription ? handleSubscribe : undefined}
                      onManage={subscription ? handleManagePlan : undefined}
                      loading={loading}
                      billingCycle={billingCycle}
                      isBestValue={isBestValue && !isActive}
                      isPopular={isPopular && !isBestValue && !isActive}
                    />
                  );
                })}
              </div>
            )}
          </div>
        </div>

        {/* Subscription History Timeline */}
        <div className="card-theme shadow">
          <div className="px-6 py-4 border-b border-theme">
            <div className="flex justify-between items-center">
              <div>
                <h3 className="text-lg font-medium text-theme-primary">Subscription History</h3>
                <p className="text-sm text-theme-secondary mt-1">Track changes to your subscription over time</p>
              </div>
              {subscriptionHistory && subscriptionHistory.history.length > 5 && (
                <button
                  onClick={() => setShowAllHistory(!showAllHistory)}
                  className="text-theme-link hover:text-theme-link-hover text-sm font-medium"
                >
                  {showAllHistory ? 'Show Less' : `Show All (${subscriptionHistory.total_events})`}
                </button>
              )}
            </div>
          </div>
          <div className="p-6">
          {historyLoading ? (
            <div className="flex items-center justify-center py-8">
              <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-theme-link"></div>
              <span className="ml-2 text-theme-secondary">Loading subscription history...</span>
            </div>
          ) : subscriptionHistory && subscriptionHistory.history.length > 0 ? (
            <div className="space-y-6">
              <div className="flow-root">
                <ul className="-mb-8">
                  {(showAllHistory ? subscriptionHistory.history : subscriptionHistory.history.slice(0, 5)).map((event, eventIdx) => (
                    <li key={event.id}>
                      <div className="relative pb-8">
                        {eventIdx !== (showAllHistory ? subscriptionHistory.history.length : Math.min(5, subscriptionHistory.history.length)) - 1 ? (
                          <span className="absolute left-4 top-4 -ml-px h-full w-0.5 bg-theme-border" aria-hidden="true" />
                        ) : null}
                        <div className="relative flex space-x-3">
                          <div>
                            <span className={`h-8 w-8 rounded-full flex items-center justify-center ring-8 ring-theme-background text-lg ${subscriptionHistoryApi.getEventColor(event.event_type)} bg-theme-background`}>
                              {subscriptionHistoryApi.getEventIcon(event.event_type)}
                            </span>
                          </div>
                          <div className="flex min-w-0 flex-1 justify-between space-x-4 pt-1.5">
                            <div>
                              <p className="text-sm text-theme-primary font-medium">
                                {subscriptionHistoryApi.formatEventType(event.event_type)}
                              </p>
                              <p className="text-sm text-theme-secondary">
                                {subscriptionHistoryApi.getEventDetails(event)}
                              </p>
                              {event.user && (
                                <p className="text-xs text-theme-secondary mt-1">
                                  by {event.user.name}
                                </p>
                              )}
                            </div>
                            <div className="whitespace-nowrap text-right text-sm text-theme-secondary">
                              <time dateTime={event.created_at}>
                                {subscriptionHistoryApi.formatRelativeTime(event.created_at)}
                              </time>
                              <div className="text-xs text-theme-secondary mt-1">
                                {subscriptionHistoryApi.formatDate(event.created_at)}
                              </div>
                            </div>
                          </div>
                        </div>
                      </div>
                    </li>
                  ))}
                </ul>
              </div>
            </div>
          ) : (
            <div className="text-center py-8">
              <div className="text-theme-secondary mb-4">
                <svg className="mx-auto h-12 w-12 text-theme-secondary" fill="none" viewBox="0 0 24 24" stroke="currentColor" aria-hidden="true">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5H7a2 2 0 00-2 2v10a2 2 0 002 2h8a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012-2m-3 7h3m-3 4h3m-6-4h.01M9 16h.01" />
                </svg>
              </div>
              <h3 className="text-sm font-medium text-theme-primary">No subscription history</h3>
              <p className="text-sm text-theme-secondary">
                {currentSubscription ? 
                  "Subscription changes and events will appear here." :
                  "Create a subscription to start tracking your subscription history."
                }
              </p>
            </div>
          )}
          </div>
        </div>
      </div>

      {/* Subscription Management Modal */}
      <SubscriptionModal
        isOpen={isModalOpen}
        onClose={() => setIsModalOpen(false)}
        subscription={selectedSubscription}
        availablePlans={availablePlans}
        onUpgrade={handleUpgrade}
        onCancel={handleCancel}
        loading={loading}
      />
    </PageContainer>
  );
};
import React, { useEffect, useState } from 'react';
import { useSelector, useDispatch } from 'react-redux';
import { RootState, AppDispatch } from '../../store';
import { fetchSubscriptions, createSubscription, updateSubscription, cancelSubscription, setAvailablePlans } from '../../store/slices/subscriptionSlice';
import { SubscriptionPlanCard } from '../../components/subscription/SubscriptionPlanCard';
import { SubscriptionModal } from '../../components/subscription/SubscriptionModal';
import { SubscriptionStatusIndicator } from '../../components/subscription/SubscriptionStatusIndicator';
import { useSubscriptionLifecycle } from '../../hooks/useSubscriptionLifecycle';
import { useSubscriptionWebSocket } from '../../hooks/useSubscriptionWebSocket';
import { Plan, Subscription } from '../../services/subscriptionService';
import { subscriptionHistoryApi, SubscriptionHistoryResponse } from '../../services/subscriptionHistoryApi';

// Mock plans data until we have a plans API endpoint
const mockPlans: Plan[] = [
  {
    id: '1',
    name: 'Starter',
    price: 999, // $9.99 in cents
    interval: 'monthly',
    features: {
      'basic_support': true,
      'api_access': true
    },
    limits: {
      users: 5,
      projects: 10,
      storage: 5
    },
    status: 'active',
    isPublic: true,
    billingCycle: 'monthly',
    currency: 'USD',
    trialDays: 14
  },
  {
    id: '2',
    name: 'Professional',
    price: 2999, // $29.99 in cents
    interval: 'monthly',
    features: {
      'priority_support': true,
      'api_access': true,
      'advanced_analytics': true
    },
    limits: {
      users: 25,
      projects: 100,
      storage: 50
    },
    status: 'active',
    isPublic: true,
    billingCycle: 'monthly',
    currency: 'USD',
    trialDays: 14
  },
  {
    id: '3',
    name: 'Enterprise',
    price: 9999, // $99.99 in cents
    interval: 'monthly',
    features: {
      'dedicated_support': true,
      'api_access': true,
      'advanced_analytics': true,
      'custom_integrations': true,
      'sso': true
    },
    limits: {
      users: -1, // unlimited
      projects: -1, // unlimited
      storage: 500
    },
    status: 'active',
    isPublic: true,
    billingCycle: 'monthly',
    currency: 'USD',
    trialDays: 30
  },
  {
    id: '4',
    name: 'Administrator',
    price: 0, // Free
    interval: 'monthly',
    features: {
      'admin_access': true,
      'all_features': true
    },
    limits: {
      users: -1,
      projects: -1,
      storage: -1
    },
    status: 'active',
    isPublic: false,
    billingCycle: 'monthly',
    currency: 'USD',
    trialDays: 0
  }
];

export const SubscriptionsPage: React.FC = () => {
  const dispatch = useDispatch<AppDispatch>();
  const { subscriptions, currentSubscription, availablePlans, loading, error } = useSelector((state: RootState) => state.subscription);
  const [selectedSubscription, setSelectedSubscription] = useState<Subscription | null>(null);
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [notification, setNotification] = useState<string | null>(null);
  const [subscriptionHistory, setSubscriptionHistory] = useState<SubscriptionHistoryResponse | null>(null);
  const [historyLoading, setHistoryLoading] = useState(false);
  const [showAllHistory, setShowAllHistory] = useState(false);

  // Use lifecycle management and real-time updates
  const { checkSubscriptionStatus, getDaysUntilExpiry } = useSubscriptionLifecycle();
  useSubscriptionWebSocket(); // Maintain realtime updates without displaying status

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
    dispatch(setAvailablePlans(mockPlans));
    
    // Fetch real subscriptions
    dispatch(fetchSubscriptions());
    
    // Load subscription history
    loadSubscriptionHistory();
  }, [dispatch]);

  const handleSubscribe = async (planId: string) => {
    try {
      const result = await dispatch(createSubscription({ planId }));
      if (createSubscription.fulfilled.match(result)) {
        setNotification('Subscription created successfully!');
        setTimeout(() => setNotification(null), 3000);
      } else {
        setNotification('Failed to create subscription. Please try again.');
        setTimeout(() => setNotification(null), 3000);
      }
    } catch (error) {
      setNotification('An error occurred. Please try again.');
      setTimeout(() => setNotification(null), 3000);
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
          data: { planId }
        }));
        if (updateSubscription.fulfilled.match(result)) {
          setNotification('Subscription upgraded successfully!');
          setIsModalOpen(false);
          setTimeout(() => setNotification(null), 3000);
        } else {
          setNotification('Failed to upgrade subscription. Please try again.');
          setTimeout(() => setNotification(null), 3000);
        }
      } catch (error) {
        setNotification('An error occurred. Please try again.');
        setTimeout(() => setNotification(null), 3000);
      }
    }
  };

  const handleCancel = async (subscriptionId: string) => {
    try {
      const result = await dispatch(cancelSubscription(subscriptionId));
      if (cancelSubscription.fulfilled.match(result)) {
        setNotification('Subscription cancelled successfully.');
        setIsModalOpen(false);
        setTimeout(() => setNotification(null), 3000);
      } else {
        setNotification('Failed to cancel subscription. Please try again.');
        setTimeout(() => setNotification(null), 3000);
      }
    } catch (error) {
      setNotification('An error occurred. Please try again.');
      setTimeout(() => setNotification(null), 3000);
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

  const formatPrice = (price: {cents: number; currency_iso: string} | number | null | undefined, interval?: string) => {
    let priceCents: number;
    
    if (price == null) {
      return 'Free';
    }
    
    if (typeof price === 'object' && 'cents' in price) {
      priceCents = price.cents;
    } else if (typeof price === 'number') {
      priceCents = price;
    } else {
      return 'Free';
    }
    
    if (priceCents === 0 || isNaN(priceCents)) {
      return 'Free';
    }
    
    const formattedPrice = (priceCents / 100).toFixed(2);
    return interval ? `$${formattedPrice}/${interval}` : `$${formattedPrice}`;
  };


  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex justify-between items-center">
        <div>
          <h1 className="text-2xl font-bold text-theme-primary">Subscriptions</h1>
          <p className="text-theme-secondary">
            Manage your subscription plans and billing settings.
          </p>
        </div>
      </div>

      {/* Notification */}
      {notification && (
        <div className={`p-4 card-theme ${notification.includes('success') ? 'bg-theme-success text-theme-success' : 'bg-theme-error text-theme-error'}`}>
          {notification}
        </div>
      )}

      {/* Error Display */}
      {error && (
        <div className="bg-theme-error text-theme-error card-theme px-4 py-3 relative">
          <span className="block sm:inline">{error}</span>
        </div>
      )}

      {/* Current Subscription Summary */}
      {currentSubscription && (
        <div className="card-theme shadow p-6">
          <h3 className="text-lg font-medium text-theme-primary mb-4">Current Subscription</h3>
          <div className="grid grid-cols-1 md:grid-cols-4 gap-4 items-start">
            <div>
              <p className="text-sm text-theme-secondary">Plan</p>
              <p className="text-lg font-medium text-theme-primary">{currentSubscription.plan.name}</p>
              <p className="text-sm text-theme-secondary">{formatPrice(currentSubscription.plan.price, currentSubscription.plan.billing_cycle)}</p>
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
                {currentSubscription.currentPeriodEnd ? 'Next Billing' : 'Billing'}
              </p>
              <p className="text-lg font-medium text-theme-primary">{formatDate(currentSubscription.currentPeriodEnd)}</p>
              <p className="text-sm text-theme-secondary">
                {currentSubscription.currentPeriodEnd ? (
                  `${getDaysUntilExpiry(currentSubscription)} days remaining`
                ) : (
                  'Never expires'
                )}
              </p>
            </div>
            <div>
              <button
                onClick={() => {
                  setSelectedSubscription(currentSubscription);
                  setIsModalOpen(true);
                }}
                className="btn-theme btn-theme-primary"
              >
                Manage Subscription
              </button>
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
          <h3 className="text-lg font-medium text-theme-primary">Available Plans</h3>
          <p className="text-sm text-theme-secondary mt-1">Choose a plan that best fits your needs</p>
        </div>
        <div className="p-6">
          {loading ? (
            <div className="flex items-center justify-center py-8">
              <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-theme-link"></div>
              <span className="ml-2 text-theme-secondary">Loading plans...</span>
            </div>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
              {availablePlans.filter(plan => plan.isPublic).map((plan) => {
                const subscription = getSubscriptionForPlan(plan.id);
                return (
                  <SubscriptionPlanCard
                    key={plan.id}
                    plan={plan}
                    isActive={!!subscription}
                    onSubscribe={!subscription ? handleSubscribe : undefined}
                    onManage={subscription ? handleManagePlan : undefined}
                    loading={loading}
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
    </div>
  );
};
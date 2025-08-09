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

  // Use lifecycle management and real-time updates
  const { checkSubscriptionStatus, getDaysUntilExpiry } = useSubscriptionLifecycle();
  useSubscriptionWebSocket(); // Maintain realtime updates without displaying status

  useEffect(() => {
    // Set mock plans (in real app, this would be an API call)
    dispatch(setAvailablePlans(mockPlans));
    
    // Fetch real subscriptions
    dispatch(fetchSubscriptions());
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

  const formatDate = (dateString: string) => {
    return new Date(dateString).toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'long',
      day: 'numeric',
    });
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
              <p className="text-sm text-theme-secondary">${(currentSubscription.plan.price / 100).toFixed(2)}/{currentSubscription.plan.interval}</p>
            </div>
            <div>
              <p className="text-sm text-theme-secondary mb-2">Status</p>
              <SubscriptionStatusIndicator 
                subscription={currentSubscription} 
                showDetails={false}
              />
            </div>
            <div>
              <p className="text-sm text-theme-secondary">Next Billing</p>
              <p className="text-lg font-medium text-theme-primary">{formatDate(currentSubscription.currentPeriodEnd)}</p>
              <p className="text-sm text-theme-secondary">
                {getDaysUntilExpiry(currentSubscription)} days remaining
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

      {/* All Subscriptions */}
      {subscriptions.length > 0 && (
        <div className="card-theme shadow">
          <div className="px-6 py-4 border-b border-theme">
            <h3 className="text-lg font-medium text-theme-primary">All Subscriptions</h3>
            <p className="text-sm text-theme-secondary mt-1">History of all your subscriptions</p>
          </div>
          <div className="overflow-hidden">
            <table className="min-w-full divide-y divide-theme">
              <thead className="bg-theme-background-secondary">
                <tr>
                  <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                    Plan
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                    Status
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                    Created
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                    Next Billing
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody className="card-theme divide-y divide-theme">
                {subscriptions.map((subscription) => (
                  <tr key={subscription.id}>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div className="text-sm font-medium text-theme-primary">{subscription.plan.name}</div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <SubscriptionStatusIndicator 
                        subscription={subscription} 
                        showDetails={false}
                      />
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-theme-primary">
                      {formatDate(subscription.createdAt)}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-theme-primary">
                      {subscription.status === 'active' ? formatDate(subscription.currentPeriodEnd) : '-'}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm font-medium">
                      {subscription.status === 'active' && (
                        <button
                          onClick={() => {
                            setSelectedSubscription(subscription);
                            setIsModalOpen(true);
                          }}
                          className="text-theme-link hover:text-theme-link-hover"
                        >
                          Manage
                        </button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

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
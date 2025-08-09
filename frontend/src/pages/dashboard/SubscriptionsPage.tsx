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
  const { refreshSubscriptions, checkSubscriptionStatus, getDaysUntilExpiry } = useSubscriptionLifecycle();
  const { connectionStatus, reconnectAttempts } = useSubscriptionWebSocket();

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

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'active':
        return 'bg-green-100 text-green-800';
      case 'trialing':
        return 'bg-blue-100 text-blue-800';
      case 'cancelled':
        return 'bg-red-100 text-red-800';
      case 'past_due':
        return 'bg-yellow-100 text-yellow-800';
      default:
        return 'bg-gray-100 text-gray-800';
    }
  };

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex justify-between items-center">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Subscriptions</h1>
          <p className="text-gray-600">
            Manage your subscription plans and billing settings.
          </p>
        </div>
        <div className="flex items-center space-x-3">
          {/* Real-time connection status */}
          <div className="flex items-center text-sm">
            <div className={`w-2 h-2 rounded-full mr-2 ${
              connectionStatus === 'connected' ? 'bg-green-500' :
              connectionStatus === 'connecting' || connectionStatus === 'reconnecting' ? 'bg-yellow-500' :
              'bg-red-500'
            }`}></div>
            <span className="text-gray-600">
              {connectionStatus === 'connected' ? 'Real-time updates active' : 
               connectionStatus === 'connecting' ? 'Connecting...' :
               connectionStatus === 'reconnecting' ? `Reconnecting... (${reconnectAttempts}/5)` :
               'Connection inactive'}
            </span>
          </div>
          <button
            onClick={() => refreshSubscriptions()}
            className="bg-gray-100 text-gray-700 px-3 py-2 rounded-md hover:bg-gray-200 transition-colors text-sm"
          >
            Refresh
          </button>
        </div>
      </div>

      {/* Notification */}
      {notification && (
        <div className={`p-4 rounded-md ${notification.includes('success') ? 'bg-green-50 text-green-700' : 'bg-red-50 text-red-700'}`}>
          {notification}
        </div>
      )}

      {/* Error Display */}
      {error && (
        <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded relative">
          <span className="block sm:inline">{error}</span>
        </div>
      )}

      {/* Current Subscription Summary */}
      {currentSubscription && (
        <div className="bg-white shadow rounded-lg p-6">
          <h3 className="text-lg font-medium text-gray-900 mb-4">Current Subscription</h3>
          <div className="grid grid-cols-1 md:grid-cols-4 gap-4 items-start">
            <div>
              <p className="text-sm text-gray-600">Plan</p>
              <p className="text-lg font-medium">{currentSubscription.plan.name}</p>
              <p className="text-sm text-gray-500">${(currentSubscription.plan.price / 100).toFixed(2)}/{currentSubscription.plan.interval}</p>
            </div>
            <div>
              <p className="text-sm text-gray-600 mb-2">Status</p>
              <SubscriptionStatusIndicator 
                subscription={currentSubscription} 
                showDetails={false}
              />
            </div>
            <div>
              <p className="text-sm text-gray-600">Next Billing</p>
              <p className="text-lg font-medium">{formatDate(currentSubscription.currentPeriodEnd)}</p>
              <p className="text-sm text-gray-500">
                {getDaysUntilExpiry(currentSubscription)} days remaining
              </p>
            </div>
            <div>
              <button
                onClick={() => {
                  setSelectedSubscription(currentSubscription);
                  setIsModalOpen(true);
                }}
                className="bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700 transition-colors"
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
      <div className="bg-white shadow rounded-lg">
        <div className="px-6 py-4 border-b border-gray-200">
          <h3 className="text-lg font-medium text-gray-900">Available Plans</h3>
          <p className="text-sm text-gray-600 mt-1">Choose a plan that best fits your needs</p>
        </div>
        <div className="p-6">
          {loading ? (
            <div className="flex items-center justify-center py-8">
              <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600"></div>
              <span className="ml-2 text-gray-600">Loading plans...</span>
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
        <div className="bg-white shadow rounded-lg">
          <div className="px-6 py-4 border-b border-gray-200">
            <h3 className="text-lg font-medium text-gray-900">All Subscriptions</h3>
            <p className="text-sm text-gray-600 mt-1">History of all your subscriptions</p>
          </div>
          <div className="overflow-hidden">
            <table className="min-w-full divide-y divide-gray-200">
              <thead className="bg-gray-50">
                <tr>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Plan
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Status
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Created
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Next Billing
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody className="bg-white divide-y divide-gray-200">
                {subscriptions.map((subscription) => (
                  <tr key={subscription.id}>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div className="text-sm font-medium text-gray-900">{subscription.plan.name}</div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <SubscriptionStatusIndicator 
                        subscription={subscription} 
                        showDetails={false}
                      />
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                      {formatDate(subscription.createdAt)}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                      {subscription.status === 'active' ? formatDate(subscription.currentPeriodEnd) : '-'}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm font-medium">
                      {subscription.status === 'active' && (
                        <button
                          onClick={() => {
                            setSelectedSubscription(subscription);
                            setIsModalOpen(true);
                          }}
                          className="text-blue-600 hover:text-blue-900"
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
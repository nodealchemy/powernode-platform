import React, { useState, useEffect } from 'react';
import { useSelector, useDispatch } from 'react-redux';
import { RootState, AppDispatch } from '@/shared/services';
import { fetchSubscriptions, createSubscription, updateSubscription, setAvailablePlans } from '@/shared/services/slices/subscriptionSlice';
import { CurrentPlanSummary } from './CurrentPlanSummary';
import { SubscriptionModal } from './SubscriptionModal';
import { useSubscriptionWebSocket } from '@/shared/hooks/useSubscriptionWebSocket';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { SubscriptionPlan, Subscription } from '@/shared/types';

interface ProfileSubscriptionTabProps {
  plans?: SubscriptionPlan[];
  loading?: boolean;
  className?: string;
  onLoadPlans?: () => Promise<SubscriptionPlan[]>;
}

export const ProfileSubscriptionTab: React.FC<ProfileSubscriptionTabProps> = ({
  plans: propPlans,
  loading: propLoading = false,
  className = '',
  onLoadPlans
}) => {
  const dispatch = useDispatch<AppDispatch>();
  const { showNotification } = useNotifications();
  const { user } = useSelector((state: RootState) => state.auth);
  const { currentSubscription, availablePlans: reduxPlans, loading: subscriptionLoading, error } = useSelector((state: RootState) => state.subscription);

  const [selectedSubscription, setSelectedSubscription] = useState<Subscription | null>(null);
  const [isModalOpen, setIsModalOpen] = useState(false);

  // Use prop plans if provided, otherwise use Redux plans
  const availablePlans = propPlans && propPlans.length > 0 ? propPlans : reduxPlans;
  const loading = propLoading || subscriptionLoading;

  // WebSocket integration for real-time updates
  useSubscriptionWebSocket({
    onSubscriptionUpdate: (_data: unknown) => {
      dispatch(fetchSubscriptions());
    },
    onSubscriptionCancelled: (_data: unknown) => {
      dispatch(fetchSubscriptions());
    },
    onPaymentProcessed: (_data: unknown) => {
      dispatch(fetchSubscriptions());
    },
    onTrialEnding: (_data: unknown) => {
      // Could show a notification here
    },
    onError: (_error: string) => {
      // Handle WebSocket errors silently in profile context
    }
  });

  // Load subscription data
  useEffect(() => {
    // Load plans via callback if provided and no prop plans
    if (!propPlans?.length && onLoadPlans) {
      onLoadPlans().then(loadedPlans => {
        dispatch(setAvailablePlans(loadedPlans));
      }).catch(() => {
        // Plans loading failed - will show empty state
      });
    }

    // Fetch real subscriptions
    dispatch(fetchSubscriptions());
  }, [dispatch, propPlans, onLoadPlans]);

  const handlePlanSelect = async (planId: string) => {
    try {
      if (currentSubscription) {
        // Update existing subscription
        const result = await dispatch(updateSubscription({
          id: currentSubscription.id,
          data: { plan_id: planId }
        }));
        
        if (updateSubscription.fulfilled.match(result)) {
          showNotification('Plan updated successfully!', 'success');
        } else {
          showNotification('Failed to update plan. Please try again.', 'error');
        }
      } else {
        // Create new subscription
        const result = await dispatch(createSubscription({ plan_id: planId }));

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
    window.location.href = '/app/account/billing';
  };

  // Check if user has billing permissions
  const canViewBilling = user?.permissions?.includes('billing.read') || user?.permissions?.includes('billing.manage');
  const canManageBilling = user?.permissions?.includes('billing.manage');

  if (!canViewBilling) {
    return (
      <div className={`text-sm text-theme-secondary ${className}`}>
        You don't have permission to view billing information.
      </div>
    );
  }

  return (
    <div className={`space-y-4 ${className}`}>
      {error && (
        <div className="text-sm text-theme-danger">
          {error} <button onClick={handleRefresh} className="underline">Retry</button>
        </div>
      )}

      <CurrentPlanSummary
        subscription={currentSubscription}
        loading={loading}
        onManage={canManageBilling ? handleManageSubscription : undefined}
      />

      {canManageBilling && !loading && (
        <button
          onClick={handleBillingManagement}
          className="text-sm text-theme-link hover:underline"
        >
          Manage billing →
        </button>
      )}

      <SubscriptionModal
        isOpen={isModalOpen}
        onClose={() => setIsModalOpen(false)}
        subscription={selectedSubscription}
        availablePlans={availablePlans}
        onUpgrade={handlePlanSelect}
        onCancel={async (_subscriptionId: string) => {
          showNotification('Subscription cancellation processed.', 'success');
          setIsModalOpen(false);
          dispatch(fetchSubscriptions());
        }}
        loading={loading}
      />
    </div>
  );
};
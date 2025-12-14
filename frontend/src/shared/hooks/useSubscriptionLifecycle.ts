import { useEffect, useCallback } from 'react';
import { useSelector, useDispatch } from 'react-redux';
import { RootState, AppDispatch } from '@/shared/services';
import { fetchSubscriptions, setCurrentSubscription } from '../services/slices/subscriptionSlice';
import { Subscription } from '@/shared/types';
import { useSubscriptionWebSocket } from './useSubscriptionWebSocket';

export interface SubscriptionLifecycleHook {
  refreshSubscriptions: () => Promise<void>;
  checkSubscriptionStatus: (subscription: Subscription) => 'active' | 'expiring' | 'expired' | 'trial_ending';
  getDaysUntilExpiry: (subscription: Subscription) => number;
  isTrialEnding: (subscription: Subscription) => boolean;
  isExpiringSoon: (subscription: Subscription) => boolean;
  getCurrentSubscription: () => Subscription | null;
  isConnected: boolean;
}

export const useSubscriptionLifecycle = (): SubscriptionLifecycleHook => {
  const dispatch = useDispatch<AppDispatch>();
  const { subscriptions, currentSubscription } = useSelector((state: RootState) => state.subscription);

  // WebSocket hook for real-time subscription updates (replaces polling)
  const { isConnected } = useSubscriptionWebSocket({
    onSubscriptionUpdate: () => {
      // Refresh subscriptions when we receive an update via WebSocket
      dispatch(fetchSubscriptions());
    },
    onSubscriptionCancelled: () => {
      dispatch(fetchSubscriptions());
    },
    onPaymentProcessed: () => {
      dispatch(fetchSubscriptions());
    },
    onTrialEnding: () => {
      dispatch(fetchSubscriptions());
    }
  });

  // Update current subscription when subscriptions change
  useEffect(() => {
    if (subscriptions.length > 0 && !currentSubscription) {
      const activeSubscription = subscriptions.find(sub => sub.status === 'active');
      if (activeSubscription) {
        dispatch(setCurrentSubscription(activeSubscription));
      }
    }
  }, [subscriptions, currentSubscription, dispatch]);

  const refreshSubscriptions = useCallback(async () => {
    await dispatch(fetchSubscriptions());
  }, [dispatch]);

  const getDaysUntilExpiry = useCallback((subscription: Subscription): number => {
    const expiryDate = new Date(subscription.current_period_end);
    const now = new Date();
    const diffTime = expiryDate.getTime() - now.getTime();
    const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24));
    return Math.max(0, diffDays);
  }, []);

  const isTrialEnding = useCallback((subscription: Subscription): boolean => {
    if (subscription.status !== 'trialing' || !subscription.trial_end) {
      return false;
    }

    const trialEndDate = new Date(subscription.trial_end);
    const now = new Date();
    const diffTime = trialEndDate.getTime() - now.getTime();
    const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24));
    
    return diffDays <= 7 && diffDays > 0; // Trial ending within 7 days
  }, []);

  const isExpiringSoon = useCallback((subscription: Subscription): boolean => {
    if (subscription.status !== 'active') {
      return false;
    }
    
    const daysUntilExpiry = getDaysUntilExpiry(subscription);
    return daysUntilExpiry <= 7 && daysUntilExpiry > 0; // Expiring within 7 days
  }, [getDaysUntilExpiry]);

  const checkSubscriptionStatus = useCallback((subscription: Subscription): 'active' | 'expiring' | 'expired' | 'trial_ending' => {
    const now = new Date();
    
    if (subscription.status === 'trialing') {
      if (isTrialEnding(subscription)) {
        return 'trial_ending';
      }
    }
    
    if (subscription.status === 'active') {
      if (isExpiringSoon(subscription)) {
        return 'expiring';
      }
      
      const expiryDate = new Date(subscription.current_period_end);
      if (now > expiryDate) {
        return 'expired';
      }
      
      return 'active';
    }
    
    return subscription.status as 'active' | 'expiring' | 'expired' | 'trial_ending';
  }, [isTrialEnding, isExpiringSoon]);

  const getCurrentSubscription = useCallback((): Subscription | null => {
    return currentSubscription || subscriptions.find(sub => sub.status === 'active') || null;
  }, [currentSubscription, subscriptions]);

  return {
    refreshSubscriptions,
    checkSubscriptionStatus,
    getDaysUntilExpiry,
    isTrialEnding,
    isExpiringSoon,
    getCurrentSubscription,
    isConnected,
  };
};
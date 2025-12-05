import { useState, useEffect, useCallback, useRef } from 'react';
import { appSubscriptionsApi, type AppSubscription, type SubscriptionUsage, type SubscriptionAnalytics } from '../services/appSubscriptionsApi';
import { useNotifications } from '@/shared/hooks/useNotifications';

interface UseAppSubscriptionsResult {
  subscriptions: AppSubscription[];
  loading: boolean;
  error: string | null;
  pagination: {
    current_page: number;
    total_pages: number;
    total_count: number;
    per_page: number;
  } | null;
  refreshSubscriptions: () => Promise<void>;
  loadMore: () => Promise<void>;
  createSubscription: (appId: string, planId: string, configuration?: Record<string, any>) => Promise<AppSubscription | null>;
  updateSubscription: (id: string, configuration: Record<string, any>) => Promise<AppSubscription | null>;
  deleteSubscription: (id: string) => Promise<boolean>;
  pauseSubscription: (id: string, reason?: string) => Promise<AppSubscription | null>;
  resumeSubscription: (id: string) => Promise<AppSubscription | null>;
  cancelSubscription: (id: string, reason?: string) => Promise<AppSubscription | null>;
  upgradePlan: (id: string, newPlanId: string) => Promise<AppSubscription | null>;
  downgradePlan: (id: string, newPlanId: string) => Promise<AppSubscription | null>;
}

export const useAppSubscriptions = (status?: string, initialLoad = true): UseAppSubscriptionsResult => {
  const [subscriptions, setSubscriptions] = useState<AppSubscription[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [pagination, setPagination] = useState<{
    current_page: number;
    total_pages: number;
    total_count: number;
    per_page: number;
  } | null>(null);
  const { showNotification } = useNotifications();

  const loadSubscriptions = useCallback(async (page = 1, append = false) => {
    try {
      setLoading(true);
      setError(null);
      
      const response = await appSubscriptionsApi.getSubscriptions(page, 20, status);
      
      if (append) {
        setSubscriptions(prev => [...prev, ...response.data]);
      } else {
        setSubscriptions(response.data);
      }
      
      setPagination(response.pagination);
    } catch (error: unknown) {
      const httpError = error as { response?: { data?: { error?: string } } };
      const errorMessage = httpError.response?.data?.error || 'Failed to load subscriptions';
      setError(errorMessage);
      showNotification(errorMessage, 'error');
    } finally {
      setLoading(false);
    }
  }, [status, showNotification]);

  const refreshSubscriptions = useCallback(async () => {
    await loadSubscriptions(1, false);
  }, [loadSubscriptions]);

  const loadMore = useCallback(async () => {
    if (!pagination || pagination.current_page >= pagination.total_pages) return;
    await loadSubscriptions(pagination.current_page + 1, true);
  }, [loadSubscriptions, pagination]);

  const createSubscription = useCallback(async (appId: string, planId: string, configuration?: Record<string, any>): Promise<AppSubscription | null> => {
    try {
      setLoading(true);
      const newSubscription = await appSubscriptionsApi.createSubscription(appId, planId, configuration);
      
      // Add to the beginning of the list
      setSubscriptions(prev => [newSubscription, ...prev]);
      
      showNotification('Successfully subscribed to app', 'success');
      return newSubscription;
    } catch (error: unknown) {
      const httpError = error as { response?: { data?: { error?: string } } };
      const errorMessage = httpError.response?.data?.error || 'Failed to create subscription';
      showNotification(errorMessage, 'error');
      return null;
    } finally {
      setLoading(false);
    }
  }, [showNotification]);

  const updateSubscription = useCallback(async (id: string, configuration: Record<string, any>): Promise<AppSubscription | null> => {
    try {
      setLoading(true);
      const updatedSubscription = await appSubscriptionsApi.updateSubscription(id, configuration);
      
      setSubscriptions(prev => prev.map(sub => 
        sub.id === id ? updatedSubscription : sub
      ));
      
      showNotification('Subscription updated successfully', 'success');
      return updatedSubscription;
    } catch (error: unknown) {
      const httpError = error as { response?: { data?: { error?: string } } };
      const errorMessage = httpError.response?.data?.error || 'Failed to update subscription';
      showNotification(errorMessage, 'error');
      return null;
    } finally {
      setLoading(false);
    }
  }, [showNotification]);

  const deleteSubscription = useCallback(async (id: string): Promise<boolean> => {
    try {
      setLoading(true);
      await appSubscriptionsApi.deleteSubscription(id);
      
      setSubscriptions(prev => prev.filter(sub => sub.id !== id));
      showNotification('Subscription deleted successfully', 'success');
      return true;
    } catch (error: unknown) {
      const httpError = error as { response?: { data?: { error?: string } } };
      const errorMessage = httpError.response?.data?.error || 'Failed to delete subscription';
      showNotification(errorMessage, 'error');
      return false;
    } finally {
      setLoading(false);
    }
  }, [showNotification]);

  const pauseSubscription = useCallback(async (id: string, reason?: string): Promise<AppSubscription | null> => {
    try {
      setLoading(true);
      const pausedSubscription = await appSubscriptionsApi.pauseSubscription(id, reason);
      
      setSubscriptions(prev => prev.map(sub => 
        sub.id === id ? pausedSubscription : sub
      ));
      
      showNotification('Subscription paused successfully', 'success');
      return pausedSubscription;
    } catch (error: unknown) {
      const httpError = error as { response?: { data?: { error?: string } } };
      const errorMessage = httpError.response?.data?.error || 'Failed to pause subscription';
      showNotification(errorMessage, 'error');
      return null;
    } finally {
      setLoading(false);
    }
  }, [showNotification]);

  const resumeSubscription = useCallback(async (id: string): Promise<AppSubscription | null> => {
    try {
      setLoading(true);
      const resumedSubscription = await appSubscriptionsApi.resumeSubscription(id);
      
      setSubscriptions(prev => prev.map(sub => 
        sub.id === id ? resumedSubscription : sub
      ));
      
      showNotification('Subscription resumed successfully', 'success');
      return resumedSubscription;
    } catch (error: unknown) {
      const httpError = error as { response?: { data?: { error?: string } } };
      const errorMessage = httpError.response?.data?.error || 'Failed to resume subscription';
      showNotification(errorMessage, 'error');
      return null;
    } finally {
      setLoading(false);
    }
  }, [showNotification]);

  const cancelSubscription = useCallback(async (id: string, reason?: string): Promise<AppSubscription | null> => {
    try {
      setLoading(true);
      const cancelledSubscription = await appSubscriptionsApi.cancelSubscription(id, reason);
      
      setSubscriptions(prev => prev.map(sub => 
        sub.id === id ? cancelledSubscription : sub
      ));
      
      showNotification('Subscription cancelled successfully', 'success');
      return cancelledSubscription;
    } catch (error: unknown) {
      const httpError = error as { response?: { data?: { error?: string } } };
      const errorMessage = httpError.response?.data?.error || 'Failed to cancel subscription';
      showNotification(errorMessage, 'error');
      return null;
    } finally {
      setLoading(false);
    }
  }, [showNotification]);

  const upgradePlan = useCallback(async (id: string, newPlanId: string): Promise<AppSubscription | null> => {
    try {
      setLoading(true);
      const upgradedSubscription = await appSubscriptionsApi.upgradePlan(id, newPlanId);
      
      setSubscriptions(prev => prev.map(sub => 
        sub.id === id ? upgradedSubscription : sub
      ));
      
      showNotification('Plan upgraded successfully', 'success');
      return upgradedSubscription;
    } catch (error: unknown) {
      const httpError = error as { response?: { data?: { error?: string } } };
      const errorMessage = httpError.response?.data?.error || 'Failed to upgrade plan';
      showNotification(errorMessage, 'error');
      return null;
    } finally {
      setLoading(false);
    }
  }, [showNotification]);

  const downgradePlan = useCallback(async (id: string, newPlanId: string): Promise<AppSubscription | null> => {
    try {
      setLoading(true);
      const downgradedSubscription = await appSubscriptionsApi.downgradePlan(id, newPlanId);
      
      setSubscriptions(prev => prev.map(sub => 
        sub.id === id ? downgradedSubscription : sub
      ));
      
      showNotification('Plan downgraded successfully', 'success');
      return downgradedSubscription;
    } catch (error: unknown) {
      const httpError = error as { response?: { data?: { error?: string } } };
      const errorMessage = httpError.response?.data?.error || 'Failed to downgrade plan';
      showNotification(errorMessage, 'error');
      return null;
    } finally {
      setLoading(false);
    }
  }, [showNotification]);

  // Load subscriptions on mount if initialLoad is true
  // StrictMode-safe: use ref to prevent duplicate calls in development
  const hasLoadedRef = useRef(false);
  const currentStatusRef = useRef(status);
  
  // Fixed render loop: removed loadSubscriptions from dependencies
  useEffect(() => {
    if (initialLoad && (!hasLoadedRef.current || currentStatusRef.current !== status)) {
      hasLoadedRef.current = true;
      currentStatusRef.current = status;
      loadSubscriptions();
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [initialLoad, status]);

  return {
    subscriptions,
    loading,
    error,
    pagination,
    refreshSubscriptions,
    loadMore,
    createSubscription,
    updateSubscription,
    deleteSubscription,
    pauseSubscription,
    resumeSubscription,
    cancelSubscription,
    upgradePlan,
    downgradePlan
  };
};

export const useSubscriptionUsage = (subscriptionId: string | null) => {
  const [usage, setUsage] = useState<SubscriptionUsage | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const { showNotification } = useNotifications();
  const hasLoadedUsageRef = useRef<string | null>(null);

  const loadUsage = useCallback(async () => {
    if (!subscriptionId) return;
    
    try {
      setLoading(true);
      setError(null);
      const usageData = await appSubscriptionsApi.getUsage(subscriptionId);
      setUsage(usageData);
    } catch (error: unknown) {
      const httpError = error as { response?: { data?: { error?: string } } };
      const errorMessage = httpError.response?.data?.error || 'Failed to load usage data';
      setError(errorMessage);
      showNotification(errorMessage, 'error');
    } finally {
      setLoading(false);
    }
  }, [subscriptionId, showNotification]);

  // Fixed render loop: removed loadUsage from dependencies
  // StrictMode-safe: prevent duplicate calls
  useEffect(() => {
    if (subscriptionId && hasLoadedUsageRef.current !== subscriptionId) {
      hasLoadedUsageRef.current = subscriptionId;
      loadUsage();
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [subscriptionId]);

  return {
    usage,
    loading,
    error,
    refreshUsage: loadUsage
  };
};

export const useSubscriptionAnalytics = (subscriptionId: string | null) => {
  const [analytics, setAnalytics] = useState<SubscriptionAnalytics | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const { showNotification } = useNotifications();
  const hasLoadedAnalyticsRef = useRef<string | null>(null);

  const loadAnalytics = useCallback(async () => {
    if (!subscriptionId) return;
    
    try {
      setLoading(true);
      setError(null);
      const analyticsData = await appSubscriptionsApi.getAnalytics(subscriptionId);
      setAnalytics(analyticsData);
    } catch (error: unknown) {
      const httpError = error as { response?: { data?: { error?: string } } };
      const errorMessage = httpError.response?.data?.error || 'Failed to load analytics data';
      setError(errorMessage);
      showNotification(errorMessage, 'error');
    } finally {
      setLoading(false);
    }
  }, [subscriptionId, showNotification]);

  // Fixed render loop: removed loadAnalytics from dependencies
  // StrictMode-safe: prevent duplicate calls
  useEffect(() => {
    if (subscriptionId && hasLoadedAnalyticsRef.current !== subscriptionId) {
      hasLoadedAnalyticsRef.current = subscriptionId;
      loadAnalytics();
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [subscriptionId]);

  return {
    analytics,
    loading,
    error,
    refreshAnalytics: loadAnalytics
  };
};
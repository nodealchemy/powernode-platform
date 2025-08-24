import { useState, useEffect, useCallback, useRef } from 'react';
import { appPlansApi } from '../services/marketplaceApi';
import type { AppPlan, AppPlanFormData } from '../types';
import { useNotification } from '@/shared/hooks/useNotification';

interface UseAppPlansResult {
  plans: AppPlan[];
  loading: boolean;
  error: string | null;
  refreshPlans: () => Promise<void>;
  createPlan: (data: AppPlanFormData) => Promise<AppPlan | null>;
  updatePlan: (id: string, data: Partial<AppPlanFormData>) => Promise<AppPlan | null>;
  deletePlan: (id: string) => Promise<boolean>;
  activatePlan: (id: string) => Promise<AppPlan | null>;
  deactivatePlan: (id: string) => Promise<AppPlan | null>;
}

export const useAppPlans = (appId: string | null | undefined, initialLoad = true): UseAppPlansResult => {
  const [plans, setPlans] = useState<AppPlan[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const { showNotification } = useNotification();
  const hasLoadedPlansRef = useRef<string | null>(null);

  const loadPlans = useCallback(async () => {
    if (!appId) {
      setPlans([]);
      return;
    }

    try {
      setLoading(true);
      setError(null);
      
      const response = await appPlansApi.getAppPlans(appId);
      setPlans(response.data || []);
    } catch (err: any) {
      const errorMessage = err.response?.data?.error || 'Failed to load app plans';
      setError(errorMessage);
      setPlans([]);
    } finally {
      setLoading(false);
    }
  }, [appId]);

  const refreshPlans = useCallback(async () => {
    await loadPlans();
  }, [loadPlans]);

  const createPlan = useCallback(async (data: AppPlanFormData): Promise<AppPlan | null> => {
    if (!appId) return null;

    try {
      setLoading(true);
      const newPlan = await appPlansApi.createAppPlan(appId, data);
      
      setPlans(prev => [newPlan.data, ...prev]);
      showNotification('App plan created successfully', 'success');
      return newPlan.data;
    } catch (err: any) {
      const errorMessage = err.response?.data?.error || 'Failed to create app plan';
      showNotification(errorMessage, 'error');
      return null;
    } finally {
      setLoading(false);
    }
  }, [appId, showNotification]);

  const updatePlan = useCallback(async (id: string, data: Partial<AppPlanFormData>): Promise<AppPlan | null> => {
    if (!appId) return null;

    try {
      setLoading(true);
      const updatedPlan = await appPlansApi.updateAppPlan(appId, id, data);
      
      setPlans(prev => prev.map(plan => 
        plan.id === id ? updatedPlan.data : plan
      ));
      
      showNotification('App plan updated successfully', 'success');
      return updatedPlan.data;
    } catch (err: any) {
      const errorMessage = err.response?.data?.error || 'Failed to update app plan';
      showNotification(errorMessage, 'error');
      return null;
    } finally {
      setLoading(false);
    }
  }, [appId, showNotification]);

  const deletePlan = useCallback(async (id: string): Promise<boolean> => {
    if (!appId) return false;

    try {
      setLoading(true);
      await appPlansApi.deleteAppPlan(appId, id);
      
      setPlans(prev => prev.filter(plan => plan.id !== id));
      showNotification('App plan deleted successfully', 'success');
      return true;
    } catch (err: any) {
      const errorMessage = err.response?.data?.error || 'Failed to delete app plan';
      showNotification(errorMessage, 'error');
      return false;
    } finally {
      setLoading(false);
    }
  }, [appId, showNotification]);

  const activatePlan = useCallback(async (id: string): Promise<AppPlan | null> => {
    if (!appId) return null;

    try {
      setLoading(true);
      const activatedPlan = await appPlansApi.activateAppPlan(appId, id);
      
      setPlans(prev => prev.map(plan => 
        plan.id === id ? activatedPlan.data : plan
      ));
      
      showNotification('App plan activated successfully', 'success');
      return activatedPlan.data;
    } catch (err: any) {
      const errorMessage = err.response?.data?.error || 'Failed to activate app plan';
      showNotification(errorMessage, 'error');
      return null;
    } finally {
      setLoading(false);
    }
  }, [appId, showNotification]);

  const deactivatePlan = useCallback(async (id: string): Promise<AppPlan | null> => {
    if (!appId) return null;

    try {
      setLoading(true);
      const deactivatedPlan = await appPlansApi.deactivateAppPlan(appId, id);
      
      setPlans(prev => prev.map(plan => 
        plan.id === id ? deactivatedPlan.data : plan
      ));
      
      showNotification('App plan deactivated successfully', 'success');
      return deactivatedPlan.data;
    } catch (err: any) {
      const errorMessage = err.response?.data?.error || 'Failed to deactivate app plan';
      showNotification(errorMessage, 'error');
      return null;
    } finally {
      setLoading(false);
    }
  }, [appId, showNotification]);

  // Load plans on mount if initialLoad is true and appId exists
  // StrictMode-safe: prevent duplicate calls
  useEffect(() => {
    if (initialLoad && appId && hasLoadedPlansRef.current !== appId) {
      hasLoadedPlansRef.current = appId;
      loadPlans();
    }
    // Fixed render loop: removed loadPlans from dependencies
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [initialLoad, appId]);

  return {
    plans,
    loading,
    error,
    refreshPlans,
    createPlan,
    updatePlan,
    deletePlan,
    activatePlan,
    deactivatePlan
  };
};
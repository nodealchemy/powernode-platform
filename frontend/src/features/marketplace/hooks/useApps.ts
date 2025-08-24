import { useState, useEffect, useCallback, useRef } from 'react';
import { appsApi } from '../services/marketplaceApi';
import { App, AppFilters } from '../types';
import { useNotification } from '@/shared/hooks/useNotification';

export const useApps = (filters: AppFilters = {}) => {
  const [apps, setApps] = useState<App[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [pagination, setPagination] = useState({
    current_page: 1,
    total_pages: 1,
    total_count: 0,
    per_page: 20
  });
  
  const { showNotification } = useNotification();

  const loadApps = useCallback(async (newFilters: AppFilters = {}) => {
    setLoading(true);
    setError(null);
    
    try {
      const response = await appsApi.getApps({ ...filters, ...newFilters });
      
      if (response.success) {
        setApps(response.data);
        setPagination(response.pagination);
      } else {
        setError('Failed to load apps');
      }
    } catch (err) {
      setError('Failed to load apps');
      console.error('Error loading apps:', err);
    } finally {
      setLoading(false);
    }
  }, [filters]);

  // StrictMode-safe: use ref to prevent duplicate calls in development
  const hasLoadedAppsRef = useRef(false);
  const currentFiltersRef = useRef<string>('');
  
  useEffect(() => {
    const filtersKey = JSON.stringify({ status: filters.status, search: filters.search, sort: filters.sort, page: filters.page });
    if (!hasLoadedAppsRef.current || currentFiltersRef.current !== filtersKey) {
      hasLoadedAppsRef.current = true;
      currentFiltersRef.current = filtersKey;
      loadApps();
    }
    // Fixed render loop: removed loadApps from dependencies
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [filters.status, filters.search, filters.sort, filters.page]);

  const createApp = async (data: any) => {
    try {
      const response = await appsApi.createApp(data);
      
      if (response.success) {
        showNotification(response.message || 'App created successfully', 'success');
        await loadApps(); // Refresh the list
        return response.data;
      } else {
        showNotification(response.error || 'Failed to create app', 'error');
        return null;
      }
    } catch (err) {
      showNotification('Failed to create app', 'error');
      console.error('Error creating app:', err);
      return null;
    }
  };

  const updateApp = async (id: string, data: any) => {
    try {
      const response = await appsApi.updateApp(id, data);
      
      if (response.success) {
        showNotification(response.message || 'App updated successfully', 'success');
        await loadApps(); // Refresh the list
        return response.data;
      } else {
        showNotification(response.error || 'Failed to update app', 'error');
        return null;
      }
    } catch (err) {
      showNotification('Failed to update app', 'error');
      console.error('Error updating app:', err);
      return null;
    }
  };

  const deleteApp = async (id: string) => {
    try {
      const response = await appsApi.deleteApp(id);
      
      if (response.success) {
        showNotification(response.message || 'App deleted successfully', 'success');
        await loadApps(); // Refresh the list
        return true;
      } else {
        showNotification(response.error || 'Failed to delete app', 'error');
        return false;
      }
    } catch (err) {
      showNotification('Failed to delete app', 'error');
      console.error('Error deleting app:', err);
      return false;
    }
  };

  const publishApp = async (id: string) => {
    try {
      const response = await appsApi.publishApp(id);
      
      if (response.success) {
        showNotification(response.message || 'App published successfully', 'success');
        await loadApps(); // Refresh the list
        return response.data;
      } else {
        showNotification(response.error || 'Failed to publish app', 'error');
        return null;
      }
    } catch (err) {
      showNotification('Failed to publish app', 'error');
      console.error('Error publishing app:', err);
      return null;
    }
  };

  const unpublishApp = async (id: string) => {
    try {
      const response = await appsApi.unpublishApp(id);
      
      if (response.success) {
        showNotification(response.message || 'App unpublished successfully', 'success');
        await loadApps(); // Refresh the list
        return response.data;
      } else {
        showNotification(response.error || 'Failed to unpublish app', 'error');
        return null;
      }
    } catch (err) {
      showNotification('Failed to unpublish app', 'error');
      console.error('Error unpublishing app:', err);
      return null;
    }
  };

  const submitForReview = async (id: string) => {
    try {
      const response = await appsApi.submitForReview(id);
      
      if (response.success) {
        showNotification(response.message || 'App submitted for review successfully', 'success');
        await loadApps(); // Refresh the list
        return response.data;
      } else {
        showNotification(response.error || 'Failed to submit app for review', 'error');
        return null;
      }
    } catch (err) {
      showNotification('Failed to submit app for review', 'error');
      console.error('Error submitting app for review:', err);
      return null;
    }
  };

  const refresh = () => loadApps();

  return {
    apps,
    loading,
    error,
    pagination,
    createApp,
    updateApp,
    deleteApp,
    publishApp,
    unpublishApp,
    submitForReview,
    refresh,
    loadApps
  };
};

export const useApp = (id: string) => {
  const [app, setApp] = useState<App | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  
  const { showNotification } = useNotification();
  const hasLoadedAppRef = useRef<string | null>(null);

  const loadApp = useCallback(async () => {
    setLoading(true);
    setError(null);
    
    try {
      const response = await appsApi.getApp(id);
      
      if (response.success) {
        setApp(response.data);
      } else {
        setError(response.error || 'Failed to load app');
      }
    } catch (err) {
      setError('Failed to load app');
      console.error('Error loading app:', err);
    } finally {
      setLoading(false);
    }
  }, [id]);

  // StrictMode-safe: prevent duplicate calls
  useEffect(() => {
    if (id && hasLoadedAppRef.current !== id) {
      hasLoadedAppRef.current = id;
      loadApp();
    }
    // Fixed render loop: removed loadApp from dependencies
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id]);

  const updateApp = async (data: any) => {
    try {
      const response = await appsApi.updateApp(id, data);
      
      if (response.success) {
        showNotification(response.message || 'App updated successfully', 'success');
        setApp(response.data);
        return response.data;
      } else {
        showNotification(response.error || 'Failed to update app', 'error');
        return null;
      }
    } catch (err) {
      showNotification('Failed to update app', 'error');
      console.error('Error updating app:', err);
      return null;
    }
  };

  const refresh = () => loadApp();

  return {
    app,
    loading,
    error,
    updateApp,
    refresh
  };
};
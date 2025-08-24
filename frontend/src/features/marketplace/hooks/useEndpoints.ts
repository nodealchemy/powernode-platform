import { useState, useEffect, useCallback, useRef } from 'react';
import { appEndpointsApi } from '../services/endpointsApi';
import { AppEndpoint, AppEndpointFilters, AppEndpointFormData } from '../types';
import { useNotification } from '@/shared/hooks/useNotification';

export const useAppEndpoints = (appId: string, filters: AppEndpointFilters = {}) => {
  const [endpoints, setEndpoints] = useState<AppEndpoint[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const hasLoadedEndpointsRef = useRef<string>('');
  const [pagination, setPagination] = useState({
    current_page: 1,
    total_pages: 1,
    total_count: 0,
    per_page: 20
  });
  
  const { showNotification } = useNotification();

  const loadEndpoints = useCallback(async (newFilters: AppEndpointFilters = {}) => {
    if (!appId) return;
    
    setLoading(true);
    setError(null);
    
    try {
      const response = await appEndpointsApi.getEndpoints(appId, { ...filters, ...newFilters });
      setEndpoints(response.data);
      setPagination(response.pagination);
    } catch (err) {
      setError('Failed to load API endpoints');
      console.error('Error loading endpoints:', err);
    } finally {
      setLoading(false);
    }
  }, [appId, filters]);

  // StrictMode-safe: prevent duplicate calls
  useEffect(() => {
    const filtersKey = JSON.stringify({ appId, search: filters.search, method: filters.method, active: filters.active, version: filters.version, page: filters.page });
    if (hasLoadedEndpointsRef.current !== filtersKey) {
      hasLoadedEndpointsRef.current = filtersKey;
      loadEndpoints();
    }
    // Fixed render loop: removed loadEndpoints from dependencies
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [appId, filters.search, filters.method, filters.active, filters.version, filters.page]);

  const createEndpoint = async (data: AppEndpointFormData) => {
    try {
      const endpoint = await appEndpointsApi.createEndpoint(appId, data);
      showNotification('API endpoint created successfully', 'success');
      await loadEndpoints();
      return endpoint;
    } catch (err) {
      showNotification('Failed to create API endpoint', 'error');
      console.error('Error creating endpoint:', err);
      return null;
    }
  };

  const updateEndpoint = async (endpointId: string, data: Partial<AppEndpointFormData>) => {
    try {
      const endpoint = await appEndpointsApi.updateEndpoint(appId, endpointId, data);
      showNotification('API endpoint updated successfully', 'success');
      await loadEndpoints();
      return endpoint;
    } catch (err) {
      showNotification('Failed to update API endpoint', 'error');
      console.error('Error updating endpoint:', err);
      return null;
    }
  };

  const deleteEndpoint = async (endpointId: string) => {
    try {
      await appEndpointsApi.deleteEndpoint(appId, endpointId);
      showNotification('API endpoint deleted successfully', 'success');
      await loadEndpoints();
      return true;
    } catch (err) {
      showNotification('Failed to delete API endpoint', 'error');
      console.error('Error deleting endpoint:', err);
      return false;
    }
  };

  const activateEndpoint = async (endpointId: string) => {
    try {
      await appEndpointsApi.activateEndpoint(appId, endpointId);
      showNotification('API endpoint activated successfully', 'success');
      await loadEndpoints();
      return true;
    } catch (err) {
      showNotification('Failed to activate API endpoint', 'error');
      console.error('Error activating endpoint:', err);
      return false;
    }
  };

  const deactivateEndpoint = async (endpointId: string) => {
    try {
      await appEndpointsApi.deactivateEndpoint(appId, endpointId);
      showNotification('API endpoint deactivated successfully', 'success');
      await loadEndpoints();
      return true;
    } catch (err) {
      showNotification('Failed to deactivate API endpoint', 'error');
      console.error('Error deactivating endpoint:', err);
      return false;
    }
  };

  const testEndpoint = async (endpointId: string, testData?: any, testHeaders?: Record<string, string>) => {
    try {
      const result = await appEndpointsApi.testEndpoint(appId, endpointId, testData, testHeaders);
      showNotification('API endpoint test completed successfully', 'success');
      return result;
    } catch (err) {
      showNotification('Failed to test API endpoint', 'error');
      console.error('Error testing endpoint:', err);
      return null;
    }
  };

  const refresh = () => loadEndpoints();

  return {
    endpoints,
    loading,
    error,
    pagination,
    createEndpoint,
    updateEndpoint,
    deleteEndpoint,
    activateEndpoint,
    deactivateEndpoint,
    testEndpoint,
    refresh,
    loadEndpoints
  };
};

export const useAppEndpoint = (appId: string, endpointId: string) => {
  const [endpoint, setEndpoint] = useState<AppEndpoint | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  
  const { showNotification } = useNotification();

  const loadEndpoint = useCallback(async () => {
    if (!appId || !endpointId) return;
    
    setLoading(true);
    setError(null);
    
    try {
      const data = await appEndpointsApi.getEndpoint(appId, endpointId);
      setEndpoint(data);
    } catch (err) {
      setError('Failed to load API endpoint');
      console.error('Error loading endpoint:', err);
    } finally {
      setLoading(false);
    }
  }, [appId, endpointId]);

  useEffect(() => {
    loadEndpoint();
  }, [appId, endpointId, loadEndpoint]);

  const updateEndpoint = async (data: Partial<AppEndpointFormData>) => {
    try {
      const updatedEndpoint = await appEndpointsApi.updateEndpoint(appId, endpointId, data);
      showNotification('API endpoint updated successfully', 'success');
      setEndpoint(updatedEndpoint);
      return updatedEndpoint;
    } catch (err) {
      showNotification('Failed to update API endpoint', 'error');
      console.error('Error updating endpoint:', err);
      return null;
    }
  };

  const getAnalytics = async (days: number = 30) => {
    try {
      return await appEndpointsApi.getEndpointAnalytics(appId, endpointId, days);
    } catch (err) {
      showNotification('Failed to load endpoint analytics', 'error');
      console.error('Error loading analytics:', err);
      return null;
    }
  };

  const refresh = () => loadEndpoint();

  return {
    endpoint,
    loading,
    error,
    updateEndpoint,
    getAnalytics,
    refresh
  };
};
import { useState, useEffect, useCallback, useRef } from 'react';
import { appWebhooksApi } from '../services/webhooksApi';
import { AppWebhook, AppWebhookFilters, AppWebhookFormData } from '../types';
import { useNotification } from '@/shared/hooks/useNotification';

export const useAppWebhooks = (appId: string, filters: AppWebhookFilters = {}) => {
  const [webhooks, setWebhooks] = useState<AppWebhook[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const hasLoadedWebhooksRef = useRef<string>('');
  const [pagination, setPagination] = useState({
    current_page: 1,
    total_pages: 1,
    total_count: 0,
    per_page: 20
  });
  
  const { showNotification } = useNotification();

  const loadWebhooks = useCallback(async (newFilters: AppWebhookFilters = {}) => {
    if (!appId) return;
    
    setLoading(true);
    setError(null);
    
    try {
      const response = await appWebhooksApi.getWebhooks(appId, { ...filters, ...newFilters });
      setWebhooks(response.data);
      setPagination(response.pagination);
    } catch (err) {
      setError('Failed to load webhooks');
      console.error('Error loading webhooks:', err);
    } finally {
      setLoading(false);
    }
  }, [appId, filters]);

  // StrictMode-safe: prevent duplicate calls
  useEffect(() => {
    const filtersKey = JSON.stringify({ appId, search: filters.search, event_type: filters.event_type, active: filters.active, page: filters.page });
    if (hasLoadedWebhooksRef.current !== filtersKey) {
      hasLoadedWebhooksRef.current = filtersKey;
      loadWebhooks();
    }
    // Fixed render loop: removed loadWebhooks from dependencies
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [appId, filters.search, filters.event_type, filters.active, filters.page]);

  const createWebhook = async (data: AppWebhookFormData) => {
    try {
      const webhook = await appWebhooksApi.createWebhook(appId, data);
      showNotification('Webhook created successfully', 'success');
      await loadWebhooks();
      return webhook;
    } catch (err) {
      showNotification('Failed to create webhook', 'error');
      console.error('Error creating webhook:', err);
      return null;
    }
  };

  const updateWebhook = async (webhookId: string, data: Partial<AppWebhookFormData>) => {
    try {
      const webhook = await appWebhooksApi.updateWebhook(appId, webhookId, data);
      showNotification('Webhook updated successfully', 'success');
      await loadWebhooks();
      return webhook;
    } catch (err) {
      showNotification('Failed to update webhook', 'error');
      console.error('Error updating webhook:', err);
      return null;
    }
  };

  const deleteWebhook = async (webhookId: string) => {
    try {
      await appWebhooksApi.deleteWebhook(appId, webhookId);
      showNotification('Webhook deleted successfully', 'success');
      await loadWebhooks();
      return true;
    } catch (err) {
      showNotification('Failed to delete webhook', 'error');
      console.error('Error deleting webhook:', err);
      return false;
    }
  };

  const activateWebhook = async (webhookId: string) => {
    try {
      await appWebhooksApi.activateWebhook(appId, webhookId);
      showNotification('Webhook activated successfully', 'success');
      await loadWebhooks();
      return true;
    } catch (err) {
      showNotification('Failed to activate webhook', 'error');
      console.error('Error activating webhook:', err);
      return false;
    }
  };

  const deactivateWebhook = async (webhookId: string) => {
    try {
      await appWebhooksApi.deactivateWebhook(appId, webhookId);
      showNotification('Webhook deactivated successfully', 'success');
      await loadWebhooks();
      return true;
    } catch (err) {
      showNotification('Failed to deactivate webhook', 'error');
      console.error('Error deactivating webhook:', err);
      return false;
    }
  };

  const testWebhook = async (webhookId: string, testData?: any) => {
    try {
      const result = await appWebhooksApi.testWebhook(appId, webhookId, testData);
      showNotification('Webhook test initiated successfully', 'success');
      return result;
    } catch (err) {
      showNotification('Failed to test webhook', 'error');
      console.error('Error testing webhook:', err);
      return null;
    }
  };

  const regenerateSecret = async (webhookId: string) => {
    try {
      const result = await appWebhooksApi.regenerateSecret(appId, webhookId);
      showNotification('Webhook secret regenerated successfully', 'success');
      await loadWebhooks();
      return result;
    } catch (err) {
      showNotification('Failed to regenerate webhook secret', 'error');
      console.error('Error regenerating secret:', err);
      return null;
    }
  };

  const refresh = () => loadWebhooks();

  return {
    webhooks,
    loading,
    error,
    pagination,
    createWebhook,
    updateWebhook,
    deleteWebhook,
    activateWebhook,
    deactivateWebhook,
    testWebhook,
    regenerateSecret,
    refresh,
    loadWebhooks
  };
};

export const useAppWebhook = (appId: string, webhookId: string) => {
  const [webhook, setWebhook] = useState<AppWebhook | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  
  const { showNotification } = useNotification();

  const loadWebhook = useCallback(async () => {
    if (!appId || !webhookId) return;
    
    setLoading(true);
    setError(null);
    
    try {
      const data = await appWebhooksApi.getWebhook(appId, webhookId);
      setWebhook(data);
    } catch (err) {
      setError('Failed to load webhook');
      console.error('Error loading webhook:', err);
    } finally {
      setLoading(false);
    }
  }, [appId, webhookId]);

  useEffect(() => {
    loadWebhook();
  }, [appId, webhookId, loadWebhook]);

  const updateWebhook = async (data: Partial<AppWebhookFormData>) => {
    try {
      const updatedWebhook = await appWebhooksApi.updateWebhook(appId, webhookId, data);
      showNotification('Webhook updated successfully', 'success');
      setWebhook(updatedWebhook);
      return updatedWebhook;
    } catch (err) {
      showNotification('Failed to update webhook', 'error');
      console.error('Error updating webhook:', err);
      return null;
    }
  };

  const getAnalytics = async (days: number = 30) => {
    try {
      return await appWebhooksApi.getWebhookAnalytics(appId, webhookId, days);
    } catch (err) {
      showNotification('Failed to load webhook analytics', 'error');
      console.error('Error loading analytics:', err);
      return null;
    }
  };

  const getDeliveries = async (filters: any = {}) => {
    try {
      return await appWebhooksApi.getWebhookDeliveries(appId, webhookId, filters);
    } catch (err) {
      showNotification('Failed to load webhook deliveries', 'error');
      console.error('Error loading deliveries:', err);
      return null;
    }
  };

  const refresh = () => loadWebhook();

  return {
    webhook,
    loading,
    error,
    updateWebhook,
    getAnalytics,
    getDeliveries,
    refresh
  };
};
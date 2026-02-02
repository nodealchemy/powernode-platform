import { useState, useEffect, useCallback, useRef } from 'react';
import { providersApi } from '@/shared/services/ai/ProvidersApiService';
import type { AiProvider } from '@/shared/types/ai';
import { useNotifications } from '@/shared/hooks/useNotifications';

/**
 * Hook for managing AI providers in DevOps context.
 *
 * DevOps pipelines now use the global AiProvider system instead of a separate
 * config model. This hook provides a compatible interface for the
 * DevOps settings page while using the shared AI provider infrastructure.
 */

interface UseAiProvidersForDevopsParams {
  provider_type?: string;
  is_active?: boolean;
}

export function useAiConfigs(params: UseAiProvidersForDevopsParams = {}) {
  const [providers, setProviders] = useState<AiProvider[]>([]);
  const [meta, setMeta] = useState<{
    total: number;
    default_id: string | null;
    by_provider: Record<string, number>;
  } | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const { showNotification } = useNotifications();
  const hasLoadedRef = useRef(false);
  const currentParamsRef = useRef<string>('');

  const fetchProviders = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const response = await providersApi.getProviders({
        provider_type: params.provider_type,
      });

      // Filter to only text_generation providers (used for DevOps)
      const aiProviders = response.items.filter(p =>
        p.provider_type === 'text_generation' &&
        (params.is_active === undefined || p.is_active === params.is_active)
      );

      setProviders(aiProviders);

      // Build meta compatible with old interface
      const byProvider: Record<string, number> = {};
      aiProviders.forEach(p => {
        byProvider[p.provider_type] = (byProvider[p.provider_type] || 0) + 1;
      });

      // Find default provider (one marked as DevOps default in metadata)
      const defaultProvider = aiProviders.find(p =>
        p.metadata && (p.metadata as Record<string, unknown>)['devops_default'] === true
      );

      setMeta({
        total: aiProviders.length,
        default_id: defaultProvider?.id || null,
        by_provider: byProvider,
      });
    } catch {
      const message = err instanceof Error ? err.message : 'Failed to fetch AI providers';
      setError(message);
    } finally {
      setLoading(false);
    }
  }, [params.provider_type, params.is_active]);

  useEffect(() => {
    const paramsKey = JSON.stringify(params);
    if (!hasLoadedRef.current || currentParamsRef.current !== paramsKey) {
      hasLoadedRef.current = true;
      currentParamsRef.current = paramsKey;
      fetchProviders();
    }
     
  }, [params.provider_type, params.is_active]);

  const setDefaultConfig = async (id: string) => {
    try {
      // Update the provider's metadata to mark it as DevOps default
      const provider = providers.find(p => p.id === id);
      if (!provider) {
        showNotification('Provider not found', 'error');
        return null;
      }

      // First, unset any existing default
      const currentDefault = providers.find(p =>
        p.metadata && (p.metadata as Record<string, unknown>)['devops_default'] === true
      );

      if (currentDefault && currentDefault.id !== id) {
        await providersApi.updateProvider(currentDefault.id, {
          metadata: {
            ...currentDefault.metadata,
            cicd_default: false,
          },
        });
      }

      // Set new default
      const updated = await providersApi.updateProvider(id, {
        metadata: {
          ...provider.metadata,
          cicd_default: true,
        },
      });

      showNotification('Default AI provider for DevOps updated', 'success');
      await fetchProviders();
      return updated;
    } catch {
      showNotification('Failed to set default AI provider', 'error');
      return null;
    }
  };

  return {
    configs: providers,
    meta,
    loading,
    error,
    refresh: fetchProviders,
    setDefaultConfig,
  };
}

export function useAiConfig(id: string | null) {
  const [provider, setProvider] = useState<AiProvider | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const hasLoadedRef = useRef<string | null>(null);

  const fetchProvider = useCallback(async () => {
    if (!id) return;

    try {
      setLoading(true);
      setError(null);
      const data = await providersApi.getProvider(id);
      setProvider(data);
    } catch {
      const message = err instanceof Error ? err.message : 'Failed to fetch AI provider';
      setError(message);
    } finally {
      setLoading(false);
    }
  }, [id]);

  useEffect(() => {
    if (id && hasLoadedRef.current !== id) {
      hasLoadedRef.current = id;
      fetchProvider();
    }
     
  }, [id]);

  return {
    config: provider,
    loading,
    error,
    refresh: fetchProvider,
  };
}

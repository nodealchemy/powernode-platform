import { useState, useEffect, useCallback } from 'react';
import { swarmApi } from '../services/swarmApi';
import type { SwarmSecret, SecretFormData, SwarmConfig, ConfigFormData } from '../types';

interface UseSwarmSecretsOptions {
  clusterId: string;
  autoLoad?: boolean;
}

interface UseSwarmSecretsResult {
  secrets: SwarmSecret[];
  configs: SwarmConfig[];
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
  createSecret: (data: SecretFormData) => Promise<SwarmSecret | null>;
  deleteSecret: (secretId: string) => Promise<boolean>;
  createConfig: (data: ConfigFormData) => Promise<SwarmConfig | null>;
  deleteConfig: (configId: string) => Promise<boolean>;
}

export function useSwarmSecrets(options: UseSwarmSecretsOptions): UseSwarmSecretsResult {
  const { clusterId, autoLoad = true } = options;
  const [secrets, setSecrets] = useState<SwarmSecret[]>([]);
  const [configs, setConfigs] = useState<SwarmConfig[]>([]);
  const [isLoading, setIsLoading] = useState(autoLoad);
  const [error, setError] = useState<string | null>(null);

  const fetchSecrets = useCallback(async () => {
    if (!clusterId) return;

    setIsLoading(true);
    setError(null);

    const [secretsRes, configsRes] = await Promise.all([
      swarmApi.getSecrets(clusterId),
      swarmApi.getConfigs(clusterId),
    ]);

    if (secretsRes.success && secretsRes.data) {
      setSecrets(secretsRes.data.items ?? []);
    }
    if (configsRes.success && configsRes.data) {
      setConfigs(configsRes.data.items ?? []);
    }

    if (!secretsRes.success && !configsRes.success) {
      setError(secretsRes.error || configsRes.error || 'Failed to fetch secrets and configs');
    }

    setIsLoading(false);
  }, [clusterId]);

  useEffect(() => {
    if (autoLoad) {
      fetchSecrets();
    }
  }, [fetchSecrets, autoLoad]);

  const createSecret = useCallback(async (data: SecretFormData): Promise<SwarmSecret | null> => {
    const response = await swarmApi.createSecret(clusterId, data);
    if (response.success && response.data) {
      await fetchSecrets();
      return response.data.secret;
    }
    setError(response.error || 'Failed to create secret');
    return null;
  }, [clusterId, fetchSecrets]);

  const deleteSecret = useCallback(async (secretId: string): Promise<boolean> => {
    const response = await swarmApi.deleteSecret(clusterId, secretId);
    if (response.success) {
      await fetchSecrets();
      return true;
    }
    setError(response.error || 'Failed to delete secret');
    return false;
  }, [clusterId, fetchSecrets]);

  const createConfig = useCallback(async (data: ConfigFormData): Promise<SwarmConfig | null> => {
    const response = await swarmApi.createConfig(clusterId, data);
    if (response.success && response.data) {
      await fetchSecrets();
      return response.data.config;
    }
    setError(response.error || 'Failed to create config');
    return null;
  }, [clusterId, fetchSecrets]);

  const deleteConfig = useCallback(async (configId: string): Promise<boolean> => {
    const response = await swarmApi.deleteConfig(clusterId, configId);
    if (response.success) {
      await fetchSecrets();
      return true;
    }
    setError(response.error || 'Failed to delete config');
    return false;
  }, [clusterId, fetchSecrets]);

  return {
    secrets,
    configs,
    isLoading,
    error,
    refetch: fetchSecrets,
    createSecret,
    deleteSecret,
    createConfig,
    deleteConfig,
  };
}

import { useState, useEffect, useCallback } from 'react';
import { gitProvidersApi } from '../services/gitProvidersApi';
import {
  GitProvider,
  GitCredential,
  AvailableProvider,
  CreateCredentialData,
  ConnectionTestResult,
} from '../types';

export function useGitProviders() {
  const [providers, setProviders] = useState<GitProvider[]>([]);
  const [availableProviders, setAvailableProviders] = useState<AvailableProvider[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchProviders = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const data = await gitProvidersApi.getProviders();
      setProviders(data);
    } catch {
      setError(err instanceof Error ? err.message : 'Failed to fetch providers');
    } finally {
      setLoading(false);
    }
  }, []);

  const fetchAvailableProviders = useCallback(async () => {
    try {
      const data = await gitProvidersApi.getAvailableProviders();
      setAvailableProviders(data);
    } catch {
      console.error('Failed to fetch available providers:', err);
    }
  }, []);

  useEffect(() => {
    fetchProviders();
    fetchAvailableProviders();
  }, [fetchProviders, fetchAvailableProviders]);

  return {
    providers,
    availableProviders,
    loading,
    error,
    refresh: fetchProviders,
    refreshAvailable: fetchAvailableProviders,
  };
}

export function useGitCredentials(providerId: string | null) {
  const [credentials, setCredentials] = useState<GitCredential[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchCredentials = useCallback(async () => {
    if (!providerId) return;

    try {
      setLoading(true);
      setError(null);
      const data = await gitProvidersApi.getCredentials(providerId);
      setCredentials(data);
    } catch {
      setError(err instanceof Error ? err.message : 'Failed to fetch credentials');
    } finally {
      setLoading(false);
    }
  }, [providerId]);

  useEffect(() => {
    fetchCredentials();
  }, [fetchCredentials]);

  const createCredential = useCallback(
    async (data: CreateCredentialData) => {
      if (!providerId) throw new Error('No provider selected');

      const credential = await gitProvidersApi.createCredential(
        providerId,
        data
      );
      await fetchCredentials();
      return credential;
    },
    [providerId, fetchCredentials]
  );

  const deleteCredential = useCallback(
    async (credentialId: string) => {
      if (!providerId) throw new Error('No provider selected');

      await gitProvidersApi.deleteCredential(providerId, credentialId);
      await fetchCredentials();
    },
    [providerId, fetchCredentials]
  );

  const testCredential = useCallback(
    async (credentialId: string): Promise<ConnectionTestResult> => {
      if (!providerId) throw new Error('No provider selected');

      return gitProvidersApi.testCredential(providerId, credentialId);
    },
    [providerId]
  );

  const updateCredential = useCallback(
    async (
      credentialId: string,
      data: Partial<{ name: string; is_active: boolean; is_default: boolean; credentials?: { access_token?: string } }>
    ) => {
      if (!providerId) throw new Error('No provider selected');

      const credential = await gitProvidersApi.updateCredential(
        providerId,
        credentialId,
        data
      );
      await fetchCredentials();
      return credential;
    },
    [providerId, fetchCredentials]
  );

  const makeDefault = useCallback(
    async (credentialId: string) => {
      if (!providerId) throw new Error('No provider selected');

      await gitProvidersApi.makeDefaultCredential(providerId, credentialId);
      await fetchCredentials();
    },
    [providerId, fetchCredentials]
  );

  return {
    credentials,
    loading,
    error,
    refresh: fetchCredentials,
    createCredential,
    updateCredential,
    deleteCredential,
    testCredential,
    makeDefault,
  };
}

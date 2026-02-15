import { useState, useEffect, useCallback } from 'react';
import { socialAccountsApi } from '../services/socialAccountsApi';
import type { SocialMediaAccount, SocialPlatform, Pagination } from '../types';

interface UseSocialAccountsOptions {
  page?: number;
  perPage?: number;
  platform?: SocialPlatform;
}

export function useSocialAccounts(options: UseSocialAccountsOptions = {}) {
  const [accounts, setAccounts] = useState<SocialMediaAccount[]>([]);
  const [pagination, setPagination] = useState<Pagination | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchAccounts = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const result = await socialAccountsApi.list({
        page: options.page,
        per_page: options.perPage,
        platform: options.platform,
      });
      setAccounts(result.accounts);
      setPagination(result.pagination);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch social accounts');
    } finally {
      setLoading(false);
    }
  }, [options.page, options.perPage, options.platform]);

  useEffect(() => {
    fetchAccounts();
  }, [fetchAccounts]);

  const connectAccount = useCallback(async (data: {
    platform: SocialPlatform;
    auth_code: string;
    redirect_uri: string;
  }) => {
    const result = await socialAccountsApi.create(data);
    await fetchAccounts();
    return result;
  }, [fetchAccounts]);

  const disconnectAccount = useCallback(async (id: string) => {
    await socialAccountsApi.delete(id);
    await fetchAccounts();
  }, [fetchAccounts]);

  const testConnection = useCallback(async (id: string) => {
    return await socialAccountsApi.test(id);
  }, []);

  const refreshToken = useCallback(async (id: string) => {
    const result = await socialAccountsApi.refreshToken(id);
    await fetchAccounts();
    return result;
  }, [fetchAccounts]);

  return {
    accounts,
    pagination,
    loading,
    error,
    refresh: fetchAccounts,
    connectAccount,
    disconnectAccount,
    testConnection,
    refreshToken,
  };
}

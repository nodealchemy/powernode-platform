import { useState, useEffect, useCallback } from 'react';
import { emailListsApi } from '../services/emailListsApi';
import type {
  EmailList,
  EmailListFormData,
  EmailSubscriber,
  SubscriberStatus,
  Pagination,
} from '../types';

interface UseEmailListsOptions {
  page?: number;
  perPage?: number;
  search?: string;
}

export function useEmailLists(options: UseEmailListsOptions = {}) {
  const [emailLists, setEmailLists] = useState<EmailList[]>([]);
  const [pagination, setPagination] = useState<Pagination | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchEmailLists = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const result = await emailListsApi.list({
        page: options.page,
        per_page: options.perPage,
        search: options.search,
      });
      setEmailLists(result.email_lists);
      setPagination(result.pagination);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch email lists');
    } finally {
      setLoading(false);
    }
  }, [options.page, options.perPage, options.search]);

  useEffect(() => {
    fetchEmailLists();
  }, [fetchEmailLists]);

  const createList = useCallback(async (data: EmailListFormData) => {
    const result = await emailListsApi.create(data);
    await fetchEmailLists();
    return result;
  }, [fetchEmailLists]);

  const updateList = useCallback(async (id: string, data: Partial<EmailListFormData>) => {
    const result = await emailListsApi.update(id, data);
    await fetchEmailLists();
    return result;
  }, [fetchEmailLists]);

  const deleteList = useCallback(async (id: string) => {
    await emailListsApi.delete(id);
    await fetchEmailLists();
  }, [fetchEmailLists]);

  const importSubscribers = useCallback(async (listId: string, file: File) => {
    const result = await emailListsApi.importSubscribers(listId, file);
    await fetchEmailLists();
    return result;
  }, [fetchEmailLists]);

  return {
    emailLists,
    pagination,
    loading,
    error,
    refresh: fetchEmailLists,
    createList,
    updateList,
    deleteList,
    importSubscribers,
  };
}

interface UseSubscribersOptions {
  listId: string | null;
  page?: number;
  perPage?: number;
  status?: SubscriberStatus;
  search?: string;
}

export function useSubscribers(options: UseSubscribersOptions) {
  const [subscribers, setSubscribers] = useState<EmailSubscriber[]>([]);
  const [pagination, setPagination] = useState<Pagination | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchSubscribers = useCallback(async () => {
    if (!options.listId) return;
    try {
      setLoading(true);
      setError(null);
      const result = await emailListsApi.listSubscribers(options.listId, {
        page: options.page,
        per_page: options.perPage,
        status: options.status,
        search: options.search,
      });
      setSubscribers(result.subscribers);
      setPagination(result.pagination);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch subscribers');
    } finally {
      setLoading(false);
    }
  }, [options.listId, options.page, options.perPage, options.status, options.search]);

  useEffect(() => {
    fetchSubscribers();
  }, [fetchSubscribers]);

  const addSubscriber = useCallback(async (data: {
    email: string;
    first_name?: string;
    last_name?: string;
    metadata?: Record<string, string>;
  }) => {
    if (!options.listId) return;
    const result = await emailListsApi.addSubscriber(options.listId, data);
    await fetchSubscribers();
    return result;
  }, [options.listId, fetchSubscribers]);

  const removeSubscriber = useCallback(async (subscriberId: string) => {
    if (!options.listId) return;
    await emailListsApi.removeSubscriber(options.listId, subscriberId);
    await fetchSubscribers();
  }, [options.listId, fetchSubscribers]);

  return {
    subscribers,
    pagination,
    loading,
    error,
    refresh: fetchSubscribers,
    addSubscriber,
    removeSubscriber,
  };
}

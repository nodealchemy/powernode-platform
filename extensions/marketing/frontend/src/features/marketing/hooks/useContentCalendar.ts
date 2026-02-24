import { useState, useEffect, useCallback } from 'react';
import { contentCalendarApi } from '../services/contentCalendarApi';
import type {
  ContentCalendarEntry,
  CalendarEntryFormData,
  ContentStatus,
  CalendarEntryType,
  Pagination,
} from '../types';

interface UseContentCalendarOptions {
  page?: number;
  perPage?: number;
  startDate?: string;
  endDate?: string;
  status?: ContentStatus;
  entryType?: CalendarEntryType;
  campaignId?: string;
}

export function useContentCalendar(options: UseContentCalendarOptions = {}) {
  const [entries, setEntries] = useState<ContentCalendarEntry[]>([]);
  const [pagination, setPagination] = useState<Pagination | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchEntries = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const result = await contentCalendarApi.list({
        page: options.page,
        per_page: options.perPage,
        start_date: options.startDate,
        end_date: options.endDate,
        status: options.status,
        entry_type: options.entryType,
        campaign_id: options.campaignId,
      });
      setEntries(result.entries);
      setPagination(result.pagination);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch calendar entries');
    } finally {
      setLoading(false);
    }
  }, [options.page, options.perPage, options.startDate, options.endDate, options.status, options.entryType, options.campaignId]);

  useEffect(() => {
    fetchEntries();
  }, [fetchEntries]);

  const createEntry = useCallback(async (data: CalendarEntryFormData) => {
    const result = await contentCalendarApi.create(data);
    await fetchEntries();
    return result;
  }, [fetchEntries]);

  const updateEntry = useCallback(async (id: string, data: Partial<CalendarEntryFormData>) => {
    const result = await contentCalendarApi.update(id, data);
    await fetchEntries();
    return result;
  }, [fetchEntries]);

  const deleteEntry = useCallback(async (id: string) => {
    await contentCalendarApi.delete(id);
    await fetchEntries();
  }, [fetchEntries]);

  return {
    entries,
    pagination,
    loading,
    error,
    refresh: fetchEntries,
    createEntry,
    updateEntry,
    deleteEntry,
  };
}

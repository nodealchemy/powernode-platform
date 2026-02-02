import { useState, useEffect, useCallback, useRef } from 'react';
import { devopsSchedulesApi } from '@/services/devopsPipelinesApi';
import type { DevopsSchedule, DevopsScheduleFormData } from '@/types/devops-pipelines';
import { useNotifications } from '@/shared/hooks/useNotifications';

interface UseSchedulesParams {
  pipeline_id?: string;
  is_active?: boolean;
}

export function useSchedules(params: UseSchedulesParams = {}) {
  const [schedules, setSchedules] = useState<DevopsSchedule[]>([]);
  const [meta, setMeta] = useState<{
    total: number;
    active_count: number;
    next_due: string | null;
  } | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const { showNotification } = useNotifications();
  const hasLoadedRef = useRef(false);
  const currentParamsRef = useRef<string>('');

  const fetchSchedules = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const data = await devopsSchedulesApi.getAll(params);
      setSchedules(data.schedules);
      setMeta(data.meta);
    } catch {
      const message = err instanceof Error ? err.message : 'Failed to fetch schedules';
      setError(message);
    } finally {
      setLoading(false);
    }
  }, [params]);

  useEffect(() => {
    const paramsKey = JSON.stringify(params);
    if (!hasLoadedRef.current || currentParamsRef.current !== paramsKey) {
      hasLoadedRef.current = true;
      currentParamsRef.current = paramsKey;
      fetchSchedules();
    }
     
  }, [params.pipeline_id, params.is_active]);

  const createSchedule = async (data: DevopsScheduleFormData) => {
    try {
      const schedule = await devopsSchedulesApi.create(data);
      showNotification('Schedule created successfully', 'success');
      await fetchSchedules();
      return schedule;
    } catch {
      showNotification('Failed to create schedule', 'error');
      return null;
    }
  };

  const updateSchedule = async (id: string, data: Partial<DevopsScheduleFormData>) => {
    try {
      const schedule = await devopsSchedulesApi.update(id, data);
      showNotification('Schedule updated successfully', 'success');
      await fetchSchedules();
      return schedule;
    } catch {
      showNotification('Failed to update schedule', 'error');
      return null;
    }
  };

  const deleteSchedule = async (id: string) => {
    try {
      await devopsSchedulesApi.delete(id);
      showNotification('Schedule deleted successfully', 'success');
      await fetchSchedules();
      return true;
    } catch {
      showNotification('Failed to delete schedule', 'error');
      return false;
    }
  };

  const toggleSchedule = async (id: string) => {
    try {
      const schedule = await devopsSchedulesApi.toggle(id);
      showNotification(
        schedule.is_active ? 'Schedule enabled' : 'Schedule disabled',
        'success'
      );
      await fetchSchedules();
      return schedule;
    } catch {
      showNotification('Failed to toggle schedule', 'error');
      return null;
    }
  };

  return {
    schedules,
    meta,
    loading,
    error,
    refresh: fetchSchedules,
    createSchedule,
    updateSchedule,
    deleteSchedule,
    toggleSchedule,
  };
}

export function useSchedule(id: string | null) {
  const [schedule, setSchedule] = useState<DevopsSchedule | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const { showNotification } = useNotifications();
  const hasLoadedRef = useRef<string | null>(null);

  const fetchSchedule = useCallback(async () => {
    if (!id) return;

    try {
      setLoading(true);
      setError(null);
      const data = await devopsSchedulesApi.getById(id, true);
      setSchedule(data);
    } catch {
      const message = err instanceof Error ? err.message : 'Failed to fetch schedule';
      setError(message);
    } finally {
      setLoading(false);
    }
  }, [id]);

  useEffect(() => {
    if (id && hasLoadedRef.current !== id) {
      hasLoadedRef.current = id;
      fetchSchedule();
    }
     
  }, [id]);

  const updateSchedule = async (data: Partial<DevopsScheduleFormData>) => {
    if (!id) return null;

    try {
      const updated = await devopsSchedulesApi.update(id, data);
      showNotification('Schedule updated successfully', 'success');
      setSchedule(updated);
      return updated;
    } catch {
      showNotification('Failed to update schedule', 'error');
      return null;
    }
  };

  return {
    schedule,
    loading,
    error,
    refresh: fetchSchedule,
    updateSchedule,
  };
}

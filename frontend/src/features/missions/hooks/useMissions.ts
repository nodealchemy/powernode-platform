import { useState, useCallback, useEffect, useRef } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import { useWebSocket } from '@/shared/hooks/useWebSocket';
import { missionsApi } from '../api/missionsApi';
import type { Mission, CreateMissionParams, MissionWebSocketEvent } from '../types/mission';

const REFETCH_EVENTS = [
  'status_changed', 'phase_changed', 'mission_created',
  'mission_completed', 'mission_failed', 'mission_cancelled',
  'approval_required', 'approval_resolved',
];

export function useMissions() {
  const { user } = useSelector((state: RootState) => state.auth);
  const { subscribe, isConnected } = useWebSocket();
  const [missions, setMissions] = useState<Mission[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const fetchRef = useRef<ReturnType<typeof setTimeout>>(undefined);

  const accountId = user?.account?.id;
  const hasReadPermission = user?.permissions?.includes('ai.missions.read') ?? false;
  const hasManagePermission = user?.permissions?.includes('ai.missions.manage') ?? false;

  const fetchMissions = useCallback(async (params?: { status?: string; mission_type?: string }) => {
    setLoading(true);
    setError(null);
    try {
      const response = await missionsApi.getMissions(params);
      setMissions(response.data?.missions || []);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch missions');
    } finally {
      setLoading(false);
    }
  }, []);

  // Subscribe to account-level mission events for real-time list updates
  useEffect(() => {
    if (!isConnected || !accountId) return;

    const unsub = subscribe({
      channel: 'MissionChannel',
      params: { type: 'account', id: accountId },
      onMessage: (data: unknown) => {
        const event = data as MissionWebSocketEvent;
        if (REFETCH_EVENTS.includes(event.event)) {
          // Debounce rapid-fire events (e.g. batch status changes)
          clearTimeout(fetchRef.current);
          fetchRef.current = setTimeout(() => fetchMissions(), 300);
        }
      },
    });

    return () => {
      clearTimeout(fetchRef.current);
      if (unsub) unsub();
    };
  }, [isConnected, accountId, subscribe, fetchMissions]);

  const createMission = useCallback(async (data: CreateMissionParams) => {
    const response = await missionsApi.createMission(data);
    if (response.data?.mission) {
      setMissions(prev => [response.data.mission, ...prev]);
    }
    return response.data?.mission;
  }, []);

  const deleteMission = useCallback(async (id: string) => {
    await missionsApi.deleteMission(id);
    setMissions(prev => prev.filter(m => m.id !== id));
  }, []);

  return {
    missions,
    loading,
    error,
    isConnected,
    hasReadPermission,
    hasManagePermission,
    fetchMissions,
    createMission,
    deleteMission,
  };
}

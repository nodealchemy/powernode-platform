import { useState, useCallback, useEffect } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import { useWebSocket } from '@/shared/hooks/useWebSocket';
import { missionsApi } from '../api/missionsApi';
import type { Mission, MissionWebSocketEvent } from '../types/mission';

export function useMission(missionId: string | undefined) {
  const { user } = useSelector((state: RootState) => state.auth);
  const { subscribe, isConnected } = useWebSocket();
  const [mission, setMission] = useState<Mission | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [events, setEvents] = useState<MissionWebSocketEvent[]>([]);

  const hasManagePermission = user?.permissions?.includes('ai.missions.manage') ?? false;

  const fetchMission = useCallback(async () => {
    if (!missionId) return;
    setLoading(true);
    setError(null);
    try {
      const response = await missionsApi.getMission(missionId);
      setMission(response.data?.mission || null);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch mission');
    } finally {
      setLoading(false);
    }
  }, [missionId]);

  // WebSocket subscription
  useEffect(() => {
    if (!isConnected || !missionId) return;

    const unsub = subscribe({
      channel: 'MissionChannel',
      params: { type: 'mission', id: missionId },
      onMessage: (data: unknown) => {
        const event = data as MissionWebSocketEvent;
        setEvents(prev => [...prev, event]);
        if (['status_changed', 'phase_changed', 'approval_required'].includes(event.event)) {
          fetchMission();
        }
      },
    });

    return () => { if (unsub) unsub(); };
  }, [isConnected, missionId, subscribe, fetchMission]);

  useEffect(() => {
    fetchMission();
  }, [fetchMission]);

  const startMission = useCallback(async () => {
    if (!missionId) return;
    const response = await missionsApi.startMission(missionId);
    if (response.data?.mission) setMission(response.data.mission);
  }, [missionId]);

  const approveMission = useCallback(async (data: { comment?: string; selected_feature?: Record<string, unknown> }) => {
    if (!missionId) return;
    const response = await missionsApi.approveMission(missionId, data);
    if (response.data?.mission) setMission(response.data.mission);
  }, [missionId]);

  const rejectMission = useCallback(async (data: { comment?: string }) => {
    if (!missionId) return;
    const response = await missionsApi.rejectMission(missionId, data);
    if (response.data?.mission) setMission(response.data.mission);
  }, [missionId]);

  const pauseMission = useCallback(async () => {
    if (!missionId) return;
    const response = await missionsApi.pauseMission(missionId);
    if (response.data?.mission) setMission(response.data.mission);
  }, [missionId]);

  const cancelMission = useCallback(async (reason?: string) => {
    if (!missionId) return;
    const response = await missionsApi.cancelMission(missionId, { reason });
    if (response.data?.mission) setMission(response.data.mission);
  }, [missionId]);

  const retryPhase = useCallback(async () => {
    if (!missionId) return;
    const response = await missionsApi.retryPhase(missionId);
    if (response.data?.mission) setMission(response.data.mission);
  }, [missionId]);

  return {
    mission,
    loading,
    error,
    events,
    hasManagePermission,
    fetchMission,
    startMission,
    approveMission,
    rejectMission,
    pauseMission,
    cancelMission,
    retryPhase,
  };
}

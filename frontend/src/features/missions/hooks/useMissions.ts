import { useState, useCallback } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import { missionsApi } from '../api/missionsApi';
import type { Mission, CreateMissionParams } from '../types/mission';

export function useMissions() {
  const { user } = useSelector((state: RootState) => state.auth);
  const [missions, setMissions] = useState<Mission[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

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
    hasReadPermission,
    hasManagePermission,
    fetchMissions,
    createMission,
    deleteMission,
  };
}

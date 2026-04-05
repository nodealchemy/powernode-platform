import { useCallback } from 'react';
import { useSearchParams } from 'react-router-dom';

const MISSION_PARAM = 'mission';

/**
 * Hook to open/close the global MissionDetailModal via URL search params.
 * Works from any page — the modal is mounted in DashboardLayout.
 */
export function useMissionModal() {
  const [searchParams, setSearchParams] = useSearchParams();

  const missionId = searchParams.get(MISSION_PARAM);
  const isOpen = missionId !== null;

  const openMission = useCallback((id: string) => {
    setSearchParams((prev) => {
      const next = new URLSearchParams(prev);
      next.set(MISSION_PARAM, id);
      return next;
    });
  }, [setSearchParams]);

  const closeMission = useCallback(() => {
    setSearchParams((prev) => {
      const next = new URLSearchParams(prev);
      next.delete(MISSION_PARAM);
      return next;
    });
  }, [setSearchParams]);

  return { missionId, isOpen, openMission, closeMission } as const;
}

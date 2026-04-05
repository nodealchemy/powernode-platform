import { useCallback } from 'react';
import { useSearchParams } from 'react-router-dom';

const TEAM_PARAM = 'team';

/**
 * Hook to open/close the global TeamDetailModal via URL search params.
 * Works from any page — the modal is mounted in DashboardLayout.
 */
export function useTeamModal() {
  const [searchParams, setSearchParams] = useSearchParams();

  const teamId = searchParams.get(TEAM_PARAM);
  const isOpen = teamId !== null;

  const openTeam = useCallback((id: string) => {
    setSearchParams((prev) => {
      const next = new URLSearchParams(prev);
      next.set(TEAM_PARAM, id);
      return next;
    });
  }, [setSearchParams]);

  const closeTeam = useCallback(() => {
    setSearchParams((prev) => {
      const next = new URLSearchParams(prev);
      next.delete(TEAM_PARAM);
      return next;
    });
  }, [setSearchParams]);

  return { teamId, isOpen, openTeam, closeTeam } as const;
}

import { useCallback } from 'react';
import { useSearchParams } from 'react-router-dom';

const AGENT_PARAM = 'agent';

/**
 * Hook to open/close the global AgentDetailModal via URL search params.
 * Works from any page — the modal is mounted in DashboardLayout.
 *
 * Opening pushes a history entry so the browser back button closes the modal.
 */
export function useAgentModal() {
  const [searchParams, setSearchParams] = useSearchParams();

  const agentId = searchParams.get(AGENT_PARAM);
  const isOpen = agentId !== null;

  const openAgent = useCallback((id: string) => {
    setSearchParams((prev) => {
      const next = new URLSearchParams(prev);
      next.set(AGENT_PARAM, id);
      return next;
    });
  }, [setSearchParams]);

  const closeAgent = useCallback(() => {
    setSearchParams((prev) => {
      const next = new URLSearchParams(prev);
      next.delete(AGENT_PARAM);
      return next;
    });
  }, [setSearchParams]);

  return { agentId, isOpen, openAgent, closeAgent } as const;
}

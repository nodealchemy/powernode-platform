import { useState, useCallback, useEffect } from 'react';
import { parallelExecutionApi } from '../services/parallelExecutionApi';
import { useParallelExecutionWebSocket } from './useParallelExecutionWebSocket';
import type {
  ParallelSession,
  ParallelSessionDetail,
  ParallelSessionConfig,
  ParallelExecutionUpdate,
} from '../types';

interface UseParallelExecutionOptions {
  sessionId?: string;
  autoRefresh?: boolean;
}

export function useParallelExecution({ sessionId, autoRefresh = true }: UseParallelExecutionOptions = {}) {
  const [sessions, setSessions] = useState<ParallelSession[]>([]);
  const [selectedSession, setSelectedSession] = useState<ParallelSessionDetail | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const loadSessions = useCallback(async (filters?: Record<string, string>) => {
    try {
      setLoading(true);
      setError(null);
      const response = await parallelExecutionApi.getSessions(filters);
      setSessions(response.items || []);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load sessions');
    } finally {
      setLoading(false);
    }
  }, []);

  const loadSession = useCallback(async (id: string) => {
    try {
      setLoading(true);
      setError(null);
      const response = await parallelExecutionApi.getSession(id);
      setSelectedSession(response);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load session');
    } finally {
      setLoading(false);
    }
  }, []);

  const createSession = useCallback(async (config: ParallelSessionConfig) => {
    try {
      setLoading(true);
      setError(null);
      const result = await parallelExecutionApi.createSession(config);
      await loadSessions();
      return result;
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to create session');
      return null;
    } finally {
      setLoading(false);
    }
  }, [loadSessions]);

  const cancelSession = useCallback(async (id: string, reason?: string) => {
    try {
      setError(null);
      await parallelExecutionApi.cancelSession(id, reason);
      if (selectedSession?.id === id) {
        await loadSession(id);
      }
      await loadSessions();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to cancel session');
    }
  }, [selectedSession, loadSession, loadSessions]);

  const retryMerge = useCallback(async (id: string) => {
    try {
      setError(null);
      await parallelExecutionApi.retryMerge(id);
      if (selectedSession?.id === id) {
        await loadSession(id);
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to retry merge');
    }
  }, [selectedSession, loadSession]);

  // WebSocket for real-time updates
  const handleWebSocketUpdate = useCallback((update: ParallelExecutionUpdate) => {
    if (!selectedSession) return;

    const event = update.event;
    if (event?.startsWith('worktree_session.') || event?.startsWith('worktree.') || event?.startsWith('merge.')) {
      loadSession(selectedSession.id);
    }
  }, [selectedSession, loadSession]);

  const { isConnected } = useParallelExecutionWebSocket({
    sessionId: sessionId || selectedSession?.id,
    enabled: autoRefresh && !!(sessionId || selectedSession?.id),
    onUpdate: handleWebSocketUpdate,
  });

  useEffect(() => {
    if (sessionId) {
      loadSession(sessionId);
    }
  }, [sessionId, loadSession]);

  return {
    sessions,
    selectedSession,
    loading,
    error,
    isConnected,
    loadSessions,
    loadSession,
    createSession,
    cancelSession,
    retryMerge,
    setSelectedSession,
  };
}

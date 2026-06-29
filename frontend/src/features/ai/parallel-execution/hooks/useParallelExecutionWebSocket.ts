import { useEffect, useRef } from 'react';
import { useWebSocket } from '@/shared/hooks/useWebSocket';
import type { ParallelExecutionUpdate } from '../types';

interface UseParallelExecutionWebSocketOptions {
  sessionId?: string;
  enabled?: boolean;
  onUpdate?: (update: ParallelExecutionUpdate) => void;
}

/**
 * Subscribe to real-time parallel-execution (worktree session) updates.
 *
 * Routes through the shared WebSocket singleton (useWebSocket -> wsManager) so it
 * reuses the single app-wide ActionCable connection and the canonical
 * Redux-backed access token. It must NOT open its own raw socket or read the
 * token from localStorage: auth tokens live in Redux state (`auth.access_token`)
 * plus an HttpOnly refresh cookie, never in localStorage, so a
 * `localStorage.getItem('auth_token')` always returns null and the connection
 * silently never authenticates.
 */
export function useParallelExecutionWebSocket({
  sessionId,
  enabled = true,
  onUpdate,
}: UseParallelExecutionWebSocketOptions) {
  const { isConnected, subscribe } = useWebSocket();

  // Keep the latest callback without re-subscribing on every render.
  const onUpdateRef = useRef(onUpdate);
  onUpdateRef.current = onUpdate;

  useEffect(() => {
    if (!enabled || !sessionId || !isConnected) return;

    const unsubscribe = subscribe({
      channel: 'AiOrchestrationChannel',
      params: { type: 'worktree_session', id: sessionId },
      onMessage: (data) => {
        onUpdateRef.current?.(data as ParallelExecutionUpdate);
      },
    });

    return unsubscribe;
  }, [sessionId, enabled, isConnected, subscribe]);

  return { isConnected: isConnected && enabled && !!sessionId };
}

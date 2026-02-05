import { useEffect, useRef, useState, useCallback } from 'react';
import type { ParallelExecutionUpdate } from '../types';

interface UseParallelExecutionWebSocketOptions {
  sessionId?: string;
  enabled?: boolean;
  onUpdate?: (update: ParallelExecutionUpdate) => void;
}

export function useParallelExecutionWebSocket({
  sessionId,
  enabled = true,
  onUpdate,
}: UseParallelExecutionWebSocketOptions) {
  const [isConnected, setIsConnected] = useState(false);
  const wsRef = useRef<WebSocket | null>(null);
  const onUpdateRef = useRef(onUpdate);
  onUpdateRef.current = onUpdate;

  const connect = useCallback(() => {
    if (!sessionId || !enabled) return;

    const token = localStorage.getItem('auth_token');
    if (!token) return;

    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const wsUrl = `${protocol}//${window.location.host}/cable?token=${token}`;

    const ws = new WebSocket(wsUrl);
    wsRef.current = ws;

    ws.onopen = () => {
      // Subscribe to worktree session channel
      ws.send(JSON.stringify({
        command: 'subscribe',
        identifier: JSON.stringify({
          channel: 'AiOrchestrationChannel',
          type: 'worktree_session',
          id: sessionId,
        }),
      }));
    };

    ws.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data);

        if (data.type === 'confirm_subscription') {
          setIsConnected(true);
          return;
        }

        if (data.type === 'reject_subscription') {
          setIsConnected(false);
          return;
        }

        if (data.message) {
          onUpdateRef.current?.(data.message as ParallelExecutionUpdate);
        }
      } catch {
        // Ignore parse errors
      }
    };

    ws.onclose = () => {
      setIsConnected(false);
    };

    ws.onerror = () => {
      setIsConnected(false);
    };
  }, [sessionId, enabled]);

  useEffect(() => {
    connect();

    return () => {
      if (wsRef.current) {
        wsRef.current.close();
        wsRef.current = null;
      }
      setIsConnected(false);
    };
  }, [connect]);

  return { isConnected };
}

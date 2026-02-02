// WebSocket hook for real-time team execution monitoring
import { useEffect, useRef, useState } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';

export interface TeamExecutionUpdate {
  type: 'execution_started' | 'execution_progress' | 'execution_completed' | 'execution_failed';
  team_id: string;
  job_id?: string;
  status?: string;
  progress?: number;
  current_member?: string;

  result?: unknown;
  error?: string;
  timestamp: string;
}

interface UseTeamExecutionWebSocketOptions {
  teamId?: string;
  onUpdate?: (update: TeamExecutionUpdate) => void;
  enabled?: boolean;
}

export const useTeamExecutionWebSocket = (options: UseTeamExecutionWebSocketOptions = {}) => {
  const { teamId, onUpdate, enabled = true } = options;
  const { access_token } = useSelector((state: RootState) => state.auth);
  const wsRef = useRef<WebSocket | null>(null);
  const [isConnected, setIsConnected] = useState(false);
  const [lastUpdate, setLastUpdate] = useState<TeamExecutionUpdate | null>(null);
  const reconnectTimeoutRef = useRef<NodeJS.Timeout | undefined>(undefined);

  useEffect(() => {
    if (!enabled || !access_token) return;

    const connect = () => {
      const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
      const wsUrl = `${protocol}//${window.location.host}/cable`;

      const ws = new WebSocket(wsUrl);
      wsRef.current = ws;

      ws.onopen = () => {
        setIsConnected(true);

        // Subscribe to team execution channel
        const subscribeMessage = {
          command: 'subscribe',
          identifier: JSON.stringify({
            channel: 'TeamExecutionChannel',
            team_id: teamId
          })
        };

        ws.send(JSON.stringify(subscribeMessage));
      };

      ws.onmessage = (event) => {
        try {
          const data = JSON.parse(event.data);

          if (data.type === 'ping') return;
          if (data.type === 'welcome') return;
          if (data.type === 'confirm_subscription') {
            return;
          }

          if (data.message) {
            const update: TeamExecutionUpdate = data.message;

            setLastUpdate(update);
            onUpdate?.(update);
          }
        } catch {
          // Error parsing message - handled silently
        }
      };

      ws.onerror = () => {
        // WebSocket error - reconnection will be attempted
      };

      ws.onclose = () => {
        setIsConnected(false);

        // Attempt to reconnect after 3 seconds
        if (enabled) {
          reconnectTimeoutRef.current = setTimeout(() => {
            connect();
          }, 3000);
        }
      };
    };

    connect();

    return () => {
      if (reconnectTimeoutRef.current) {
        clearTimeout(reconnectTimeoutRef.current);
      }

      if (wsRef.current) {
        wsRef.current.close();
        wsRef.current = null;
      }
    };
  }, [teamId, access_token, enabled, onUpdate]);

  return {
    isConnected,
    lastUpdate
  };
};

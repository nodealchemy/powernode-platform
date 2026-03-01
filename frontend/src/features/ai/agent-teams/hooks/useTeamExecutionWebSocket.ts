// WebSocket hook for real-time team execution monitoring
// Uses the shared WebSocket manager (singleton connection) instead of a raw WebSocket
import { useEffect, useRef, useState, useCallback } from 'react';
import { useWebSocket } from '@/shared/hooks/useWebSocket';

export type TeamExecutionEventType =
  | 'execution_started' | 'execution_progress' | 'member_completed'
  | 'execution_completed' | 'execution_failed' | 'execution_timeout'
  | 'execution_paused' | 'execution_resumed' | 'execution_cancelled'
  | 'execution_redirected' | 'command_acknowledged' | 'command_error';

export interface TeamExecutionUpdate {
  type: TeamExecutionEventType;
  team_id: string;
  job_id?: string;
  execution_id?: string;
  status?: string;
  progress?: number;
  current_member?: string;
  current_role?: string;
  member_index?: number;
  member_name?: string;
  member_success?: boolean;
  member_duration_ms?: number;
  tasks_total?: number;
  tasks_completed?: number;
  tasks_failed?: number;
  result?: unknown;
  error?: string;
  duration_ms?: number;
  timestamp: string;
}

interface UseTeamExecutionWebSocketOptions {
  teamId?: string;
  onUpdate?: (update: TeamExecutionUpdate) => void;
  enabled?: boolean;
}

export const useTeamExecutionWebSocket = (options: UseTeamExecutionWebSocketOptions = {}) => {
  const { teamId, onUpdate, enabled = true } = options;
  const { isConnected, subscribe, sendMessage } = useWebSocket();
  const [lastUpdate, setLastUpdate] = useState<TeamExecutionUpdate | null>(null);
  const onUpdateRef = useRef(onUpdate);
  onUpdateRef.current = onUpdate;

  useEffect(() => {
    if (!enabled || !teamId || !isConnected) return;

    const unsubscribe = subscribe({
      channel: 'TeamExecutionChannel',
      params: { team_id: teamId },
      onMessage: (data) => {
        const update = data as TeamExecutionUpdate;
        setLastUpdate(update);
        onUpdateRef.current?.(update);
      },
    });

    return unsubscribe;
  }, [teamId, enabled, isConnected, subscribe]);

  const sendCommand = useCallback(
    (command: 'pause' | 'resume' | 'cancel' | 'redirect', executionId: string, instructions?: Record<string, unknown>) => {
      if (!teamId) return;

      sendMessage(
        'TeamExecutionChannel',
        command,
        {
          execution_id: executionId,
          ...(instructions ? { instructions } : {}),
        },
        { team_id: teamId }
      );
    },
    [teamId, sendMessage]
  );

  return {
    isConnected,
    lastUpdate,
    sendCommand,
  };
};

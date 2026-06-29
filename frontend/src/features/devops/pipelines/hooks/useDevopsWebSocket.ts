import { useEffect, useRef } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import { useWebSocket } from '@/shared/hooks/useWebSocket';
import type { DevopsPipelineRun } from '@/types/devops-pipelines';

export interface DevopsPipelineEvent {
  type: 'run_created' | 'run_updated' | 'run_completed' | 'step_updated' | 'subscribed';
  pipeline_run?: Partial<DevopsPipelineRun>;
  pipeline_run_id?: string;
  step_execution?: {
    id: string;
    step_name: string;
    step_type: string;
    status: string;
    started_at: string | null;
    completed_at: string | null;
    error_message: string | null;
  };
  progress_percentage?: number;
  timestamp: string;
  message?: string;
}

/**
 * Hook for subscribing to DevOps pipeline WebSocket updates.
 *
 * Routes through the shared WebSocket singleton (useWebSocket -> wsManager) so it
 * reuses the single app-wide ActionCable connection and the canonical
 * Redux-backed access token, instead of standing up a second connection manager.
 *
 * @param pipelineId - Optional pipeline ID to subscribe to specific pipeline updates
 * @param onEvent - Callback for handling events
 */
export function useDevopsWebSocket(
  pipelineId?: string,
  onEvent?: (event: DevopsPipelineEvent) => void
) {
  const accountId = useSelector((state: RootState) => state.auth.user?.account?.id);
  const { isConnected, subscribe } = useWebSocket();

  const onEventRef = useRef(onEvent);
  onEventRef.current = onEvent;

  useEffect(() => {
    if (!accountId || !isConnected) return;

    // Mirror the backend DevopsPipelineChannel#subscribed params: account-wide
    // stream when no pipeline is given, pipeline-specific stream otherwise. The
    // singleton routes incoming messages back to this subscriber by the exact
    // channel + params identifier.
    const params: Record<string, unknown> = { account_id: accountId };
    if (pipelineId) params.pipeline_id = pipelineId;

    const unsubscribe = subscribe({
      channel: 'DevopsPipelineChannel',
      params,
      onMessage: (data) => {
        const event = data as DevopsPipelineEvent;
        if (event && event.type) {
          onEventRef.current?.(event);
        }
      },
    });

    return unsubscribe;
  }, [accountId, pipelineId, isConnected, subscribe]);

  return { isConnected };
}

/**
 * Hook specifically for pipeline runs list with automatic refresh
 */
export function useDevopsRunsWebSocket(
  pipelineId: string | undefined,
  onRunCreated?: (run: Partial<DevopsPipelineRun>) => void,
  onRunUpdated?: (run: Partial<DevopsPipelineRun>) => void
) {
  const { isConnected } = useDevopsWebSocket(pipelineId, (event) => {
    if (event.type === 'run_created' && event.pipeline_run) {
      onRunCreated?.(event.pipeline_run);
    } else if ((event.type === 'run_updated' || event.type === 'run_completed') && event.pipeline_run) {
      onRunUpdated?.(event.pipeline_run);
    }
  });

  return { isConnected };
}

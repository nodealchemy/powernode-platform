import { useState, useEffect, useCallback } from 'react';
import { useWebSocket } from '@/shared/hooks/useWebSocket';
import type { CodeFactoryWebSocketEvent } from '../types/codeFactory';

interface UseCodeFactoryWebSocketProps {
  contractId?: string;
  runId?: string;
  reviewStateId?: string;
  onEvent?: (event: CodeFactoryWebSocketEvent) => void;
}

export function useCodeFactoryWebSocket({
  contractId,
  runId,
  reviewStateId,
  onEvent,
}: UseCodeFactoryWebSocketProps) {
  const { subscribe, isConnected } = useWebSocket();
  const [events, setEvents] = useState<CodeFactoryWebSocketEvent[]>([]);

  const handleMessage = useCallback(
    (data: unknown) => {
      const event = data as CodeFactoryWebSocketEvent;
      setEvents(prev => [...prev, event]);
      if (onEvent) {
        onEvent(event);
      }
    },
    [onEvent]
  );

  useEffect(() => {
    if (!isConnected) return;

    const subscriptions: Array<() => void> = [];

    if (runId) {
      const unsub = subscribe({
        channel: 'CodeFactoryChannel',
        params: { type: 'run', id: runId },
        onMessage: handleMessage,
      });
      if (unsub) subscriptions.push(unsub);
    }

    if (contractId) {
      const unsub = subscribe({
        channel: 'CodeFactoryChannel',
        params: { type: 'contract', id: contractId },
        onMessage: handleMessage,
      });
      if (unsub) subscriptions.push(unsub);
    }

    if (reviewStateId) {
      const unsub = subscribe({
        channel: 'CodeFactoryChannel',
        params: { type: 'review_state', id: reviewStateId },
        onMessage: handleMessage,
      });
      if (unsub) subscriptions.push(unsub);
    }

    return () => {
      subscriptions.forEach(unsub => unsub());
    };
  }, [isConnected, runId, contractId, reviewStateId, subscribe, handleMessage]);

  return { isConnected, events };
}

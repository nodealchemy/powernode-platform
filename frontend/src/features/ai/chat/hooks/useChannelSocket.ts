import { useEffect, useRef } from 'react';
import { useWebSocket } from '@/shared/hooks/useWebSocket';
import type { TeamChannelMessage } from '@/shared/services/ai/TeamsApiService';

interface UseChannelSocketOptions {
  channelId: string | undefined;
  onMessage: (message: TeamChannelMessage) => void;
  enabled?: boolean;
}

/**
 * Subscribes to a TeamChannelChannel via ActionCable for real-time messages.
 */
export function useChannelSocket({ channelId, onMessage, enabled = true }: UseChannelSocketOptions) {
  const { subscribe } = useWebSocket();
  const onMessageRef = useRef(onMessage);
  onMessageRef.current = onMessage;

  useEffect(() => {
    if (!channelId || !enabled) return;

    const unsubscribe = subscribe({
      channel: 'TeamChannelChannel',
      params: { channel_id: channelId },
      onMessage: (data: unknown) => {
        const event = data as Record<string, unknown>;
        if (event.type === 'message_created' && event.message) {
          onMessageRef.current(event.message as TeamChannelMessage);
        }
      },
    });

    return () => unsubscribe();
  }, [channelId, enabled, subscribe]);
}

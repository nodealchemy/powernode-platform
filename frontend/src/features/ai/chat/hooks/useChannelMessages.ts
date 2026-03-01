import { useState, useCallback, useEffect, useRef } from 'react';
import { teamsApi } from '@/shared/services/ai/TeamsApiService';
import type { TeamChannelMessage } from '@/shared/services/ai/TeamsApiService';
import { useChannelSocket } from './useChannelSocket';
import { logger } from '@/shared/utils/logger';

interface UseChannelMessagesOptions {
  teamId: string | undefined;
  channelId: string | undefined;
}

export function useChannelMessages({ teamId, channelId }: UseChannelMessagesOptions) {
  const [messages, setMessages] = useState<TeamChannelMessage[]>([]);
  const [loading, setLoading] = useState(false);
  const [sending, setSending] = useState(false);
  const loadedRef = useRef(false);

  // Fetch messages on mount / channel change
  useEffect(() => {
    if (!teamId || !channelId) return;
    loadedRef.current = false;

    const fetchMessages = async () => {
      setLoading(true);
      try {
        const { messages: msgs } = await teamsApi.listChannelMessages(teamId, channelId);
        setMessages(msgs);
        loadedRef.current = true;
      } catch (err) {
        logger.error('Failed to load channel messages', err);
      } finally {
        setLoading(false);
      }
    };

    fetchMessages();
  }, [teamId, channelId]);

  // Handle incoming WebSocket messages
  const handleSocketMessage = useCallback((msg: TeamChannelMessage) => {
    setMessages(prev => {
      // Deduplicate by ID (optimistic update may have added it already)
      if (prev.some(m => m.id === msg.id)) return prev;
      return [...prev, msg];
    });
  }, []);

  useChannelSocket({
    channelId,
    onMessage: handleSocketMessage,
    enabled: !!teamId && !!channelId,
  });

  // Send a human_input message
  const sendMessage = useCallback(async (content: string) => {
    if (!teamId || !channelId || !content.trim()) return;
    setSending(true);
    try {
      const msg = await teamsApi.sendChannelMessage(teamId, channelId, content);
      // Optimistic: add if not already present via WS
      setMessages(prev => prev.some(m => m.id === msg.id) ? prev : [...prev, msg]);
    } catch (err) {
      logger.error('Failed to send channel message', err);
      throw err;
    } finally {
      setSending(false);
    }
  }, [teamId, channelId]);

  return { messages, loading, sending, sendMessage };
}

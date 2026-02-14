import { useCallback } from 'react';
import { agentsApi } from '@/shared/services/ai';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { cleanMarkdownContent } from '@/shared/utils/markdownUtils';
import type { AiMessage } from '@/shared/types/ai';
import { mapBackendMessage } from './utils';

interface UseMessageActionsOptions {
  conversationId: string;
  agentId?: string;
  setMessages: React.Dispatch<React.SetStateAction<AiMessage[]>>;
  setEditingMessageId: React.Dispatch<React.SetStateAction<string | null>>;
  setEditSaving: React.Dispatch<React.SetStateAction<boolean>>;
  setThreadMessage: React.Dispatch<React.SetStateAction<AiMessage | null>>;
  setThreadMessages: React.Dispatch<React.SetStateAction<AiMessage[]>>;
  setThreadLoading: React.Dispatch<React.SetStateAction<boolean>>;
  threadMessage: AiMessage | null;
}

export function useMessageActions({
  conversationId,
  agentId,
  setMessages,
  setEditingMessageId,
  setEditSaving,
  setThreadMessage,
  setThreadMessages,
  setThreadLoading,
  threadMessage
}: UseMessageActionsOptions) {
  const { addNotification } = useNotifications();

  const handleCopyMessage = useCallback(async (message: AiMessage) => {
    try {
      const plainText = cleanMarkdownContent(message.content).replace(/0\s*$/, '').trim();
      await navigator.clipboard.writeText(plainText);
      addNotification({
        type: 'success',
        title: 'Copied',
        message: 'Message copied to clipboard'
      });
    } catch (_error) {
      // Error silently ignored
    }
  }, []);  

  const handleRegenerateResponse = useCallback(async (messageId: string) => {
    if (!agentId) {
      addNotification({
        type: 'error',
        title: 'Regeneration Failed',
        message: 'Unable to regenerate - missing agent information'
      });
      return;
    }

    try {
      const result = await agentsApi.regenerateMessage(agentId, conversationId, messageId);

      if (result.regeneration_queued) {
        addNotification({
          type: 'success',
          title: 'Regeneration Queued',
          message: 'AI response regeneration has been queued. New response will appear shortly.'
        });

        setMessages(prev => prev.map(msg =>
          msg.id === messageId
            ? { ...msg, metadata: { ...msg.metadata, regenerating: true } }
            : msg
        ));
      }
    } catch (_error) {
      addNotification({
        type: 'error',
        title: 'Regeneration Failed',
        message: 'Failed to regenerate AI response. Please try again.'
      });
    }
  }, [conversationId, agentId]);  

  const handleRateMessage = useCallback(async (messageId: string, rating: 'thumbs_up' | 'thumbs_down') => {
    if (!agentId) {
      addNotification({
        type: 'error',
        title: 'Rating Failed',
        message: 'Unable to rate - missing agent information'
      });
      return;
    }

    try {
      const result = await agentsApi.rateMessage(agentId, conversationId, messageId, rating);

      addNotification({
        type: 'success',
        title: 'Feedback Recorded',
        message: `Thank you for your ${rating === 'thumbs_up' ? 'positive' : 'negative'} feedback!`
      });

      setMessages(prev => prev.map(msg =>
        msg.id === messageId
          ? { ...msg, metadata: { ...msg.metadata, user_rating: result.rating } }
          : msg
      ));
    } catch (_error) {
      addNotification({
        type: 'error',
        title: 'Rating Failed',
        message: 'Failed to submit your feedback. Please try again.'
      });
    }
  }, [conversationId, agentId]);  

  const handleEditMessage = useCallback(async (messageId: string, newContent: string) => {
    if (!agentId) return;

    setEditSaving(true);
    try {
      const result = await agentsApi.editMessageContent(agentId, conversationId, messageId, newContent);
      setMessages(prev => prev.map(msg =>
        msg.id === messageId
          ? { ...msg, content: result.content || newContent, is_edited: true, edited_at: new Date().toISOString() }
          : msg
      ));
      setEditingMessageId(null);
      addNotification({ type: 'success', title: 'Saved', message: 'Message updated' });
    } catch (_error) {
      addNotification({ type: 'error', title: 'Edit Failed', message: 'Failed to update message' });
    } finally {
      setEditSaving(false);
    }
  }, [conversationId, agentId]);  

  const handleDeleteMessage = useCallback(async (message: AiMessage) => {
    if (!agentId) return;

    try {
      if (message.deleted_at) {
        // Restore
        const result = await agentsApi.restoreMessage(agentId, conversationId, message.id);
        setMessages(prev => prev.map(msg =>
          msg.id === message.id ? { ...msg, ...result.message, deleted_at: undefined } : msg
        ));
        addNotification({ type: 'success', title: 'Restored', message: 'Message restored' });
      } else {
        // Soft delete
        await agentsApi.deleteMessage(agentId, conversationId, message.id);
        setMessages(prev => prev.map(msg =>
          msg.id === message.id ? { ...msg, deleted_at: new Date().toISOString() } : msg
        ));
        addNotification({ type: 'success', title: 'Deleted', message: 'Message deleted' });
      }
    } catch (_error) {
      addNotification({ type: 'error', title: 'Action Failed', message: 'Failed to update message' });
    }
  }, [conversationId, agentId]);  

  const handleOpenThread = useCallback(async (message: AiMessage) => {
    if (!agentId) return;

    setThreadMessage(message);
    setThreadLoading(true);
    try {
      const result = await agentsApi.getMessageThread(agentId, conversationId, message.id);
      setThreadMessages((result.thread || []).map((msg: AiMessage) => mapBackendMessage(msg as unknown as Record<string, unknown>)));
    } catch (_error) {
      addNotification({ type: 'error', title: 'Thread Failed', message: 'Failed to load thread' });
      setThreadMessage(null);
    } finally {
      setThreadLoading(false);
    }
  }, [conversationId, agentId]);  

  const handleSendReply = useCallback(async (content: string) => {
    if (!agentId || !threadMessage) return;

    try {
      const result = await agentsApi.replyToMessage(agentId, conversationId, threadMessage.id, content);
      const mapped = mapBackendMessage(result.message as unknown as Record<string, unknown>);
      setThreadMessages(prev => [...prev, mapped]);
      // Update reply count on parent message
      setMessages(prev => prev.map(msg =>
        msg.id === threadMessage.id ? { ...msg, reply_count: (msg.reply_count || 0) + 1 } : msg
      ));
    } catch (_error) {
      addNotification({ type: 'error', title: 'Reply Failed', message: 'Failed to send reply' });
    }
  }, [conversationId, agentId, threadMessage]);  

  return {
    handleCopyMessage,
    handleRegenerateResponse,
    handleRateMessage,
    handleEditMessage,
    handleDeleteMessage,
    handleOpenThread,
    handleSendReply
  };
}

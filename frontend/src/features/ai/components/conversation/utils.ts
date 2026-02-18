import { cleanMarkdownContent } from '@/shared/utils/markdownUtils';
import type { AiMessage, MessageAction, ActionContext } from '@/shared/types/ai';

/**
 * Clean message content to remove chunked encoding artifacts.
 * Handles various forms of HTTP chunked transfer encoding markers.
 */
export const cleanMessageContent = (content: string): string => {
  if (!content) return '';

  // First clean markdown content for safety
  let cleaned = cleanMarkdownContent(content);

  // Comprehensive chunked encoding cleanup
  cleaned = cleaned
    // Remove trailing chunk markers (hex size followed by optional CRLF)
    ?.replace(/[\r\n]*[0-9a-fA-F]+[\r\n]*$/g, '')
    // Remove leading chunk headers (hex size at start)
    ?.replace(/^[\r\n]*[0-9a-fA-F]+[\r\n]+/g, '')
    // Remove inline chunk markers between content
    ?.replace(/\r\n[0-9a-fA-F]+\r\n/g, '')
    // Remove "0" after punctuation (final chunk marker)
    ?.replace(/([.!?])\s*0\s*$/g, '$1')
    // Remove trailing whitespace + "0" patterns
    ?.replace(/\s+0\s*$/g, '')
    // Remove standalone trailing "0" (final chunk indicator)
    ?.replace(/(?:^|\s)0$/g, '')
    ?.trim() || '';

  // Final chunk marker check - if content is just zeros, return empty
  if (/^0+$/.test(cleaned)) {
    return '';
  }

  return cleaned;
};

/**
 * Map backend message_data format to frontend AiMessage format
 */
export const mapBackendMessage = (msg: Record<string, unknown>): AiMessage => {
  const role = (msg.role as string) || 'user';
  const senderType = role === 'assistant' ? 'ai' : (role as 'user' | 'system');

  return {
    id: (msg.id as string) || (msg.message_id as string) || '',
    sender_type: (msg.sender_type as 'user' | 'ai' | 'system') || senderType,
    sender_info: (msg.sender_info as AiMessage['sender_info']) || {
      name: (msg.user as string) || (role === 'assistant' ? 'AI Assistant' : 'User')
    },
    content: cleanMessageContent((msg.content as string) || ''),
    created_at: (msg.created_at as string) || new Date().toISOString(),
    is_edited: msg.is_edited as boolean | undefined,
    edited_at: msg.edited_at as string | undefined,
    deleted_at: msg.deleted_at as string | undefined,
    parent_message_id: msg.parent_message_id as string | undefined,
    reply_count: msg.reply_count as number | undefined,
    user_id: msg.user_id as string | undefined,
    metadata: {
      ...((msg.metadata as AiMessage['metadata']) || {
        timestamp: (msg.created_at as string) || new Date().toISOString(),
        tokens_used: msg.token_count as number | undefined,
        cost_estimate: msg.cost_usd ? parseFloat(String(msg.cost_usd)) || 0 : undefined,
        processing: (msg.status as string) === 'processing',
        error: (msg.status as string) === 'failed'
      }),
      ...(msg.content_metadata ? {
        actions: (msg.content_metadata as Record<string, unknown>).actions as MessageAction[] | undefined,
        action_context: (msg.content_metadata as Record<string, unknown>).action_context as ActionContext | undefined,
        concierge_action: (msg.content_metadata as Record<string, unknown>).concierge_action as string | undefined,
        action_params: (msg.content_metadata as Record<string, unknown>).action_params as Record<string, unknown> | undefined,
      } : {})
    }
  };
};

/**
 * Format a timestamp to a short time string
 */
export const formatTimestamp = (timestamp: string): string => {
  return new Date(timestamp).toLocaleTimeString([], {
    hour: '2-digit',
    minute: '2-digit'
  });
};

import { cleanMarkdownContent } from '@/shared/utils/markdownUtils';
import type { AiMessage, MessageAction, ActionContext } from '@/shared/types/ai';

/**
 * Clean AI streaming content to remove chunked encoding artifacts.
 * Only safe for AI/assistant messages — the hex-stripping regexes will
 * eat trailing hex chars (a-f, 0-9) from normal English words.
 *
 * NEVER apply to user messages.
 */
export const cleanStreamingContent = (content: string): string => {
  if (!content) return '';

  let cleaned = cleanMarkdownContent(content);

  // Chunked encoding cleanup — only safe for streaming AI responses
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
 * Clean message content — applies markdown sanitization to all messages,
 * but only applies chunked encoding cleanup to AI responses.
 */
export const cleanMessageContent = (content: string, role?: string): string => {
  if (!content) return '';

  // AI/assistant messages may have chunked encoding artifacts from streaming
  if (role === 'assistant' || role === 'ai') {
    return cleanStreamingContent(content);
  }

  // User/system messages: only sanitize markdown, never strip trailing chars
  return cleanMarkdownContent(content) || '';
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
    content: cleanMessageContent((msg.content as string) || '', role),
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
        mentions: (msg.content_metadata as Record<string, unknown>).mentions as Array<{ id: string; name: string }> | undefined,
      } : {})
    }
  };
};

/** Part of a parsed mention string */
export interface MentionPart {
  type: 'text' | 'mention';
  value: string;
}

/**
 * Parse @mentions in text using known mention names from message metadata.
 * Returns structured parts that components can render with highlighting.
 * Only highlights when exact mention names are provided (no guessing).
 */
export function parseMentions(
  text: string,
  mentionNames?: string[]
): MentionPart[] {
  if (!text || !mentionNames || mentionNames.length === 0) {
    return [{ type: 'text', value: text || '' }];
  }

  // Sort longest first to avoid partial matches (e.g. "Claude Code" before "Claude")
  const sorted = [...mentionNames].sort((a, b) => b.length - a.length);
  const escaped = sorted.map(name => name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'));
  const pattern = new RegExp(`(@(?:${escaped.join('|')}))`, 'g');

  const parts: MentionPart[] = [];
  let lastIndex = 0;
  let match: RegExpExecArray | null;

  while ((match = pattern.exec(text)) !== null) {
    if (match.index > lastIndex) {
      parts.push({ type: 'text', value: text.slice(lastIndex, match.index) });
    }
    parts.push({ type: 'mention', value: match[1] });
    lastIndex = pattern.lastIndex;
  }

  if (lastIndex < text.length) {
    parts.push({ type: 'text', value: text.slice(lastIndex) });
  }

  return parts.length > 0 ? parts : [{ type: 'text', value: text }];
}

/**
 * Format a timestamp to a short time string
 */
export const formatTimestamp = (timestamp: string): string => {
  return new Date(timestamp).toLocaleTimeString([], {
    hour: '2-digit',
    minute: '2-digit'
  });
};

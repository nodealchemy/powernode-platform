import React, { useMemo } from 'react';
import ReactMarkdown from 'react-markdown';

interface ChatStreamingRendererProps {
  content: string;
  isStreaming: boolean;
  tokenCount?: number;
  elapsedMs?: number;
  cost?: number;
}

export const ChatStreamingRenderer: React.FC<ChatStreamingRendererProps> = ({
  content,
  isStreaming,
  tokenCount,
  elapsedMs,
  cost,
}) => {
  // Sanitize partial markdown that might be mid-tag during streaming
  const safeContent = useMemo(() => {
    if (!content) return '';
    if (!isStreaming) return content;

    let cleaned = content;

    // Close any unclosed code blocks (odd number of ```)
    const codeBlockCount = (cleaned.match(/```/g) || []).length;
    if (codeBlockCount % 2 !== 0) {
      cleaned += '\n```';
    }

    // Close any unclosed inline code (odd number of single `)
    const inlineCodeCount = (cleaned.match(/(?<!`)`(?!`)/g) || []).length;
    if (inlineCodeCount % 2 !== 0) {
      cleaned += '`';
    }

    return cleaned;
  }, [content, isStreaming]);

  if (!content) {
    return isStreaming ? (
      <div className="flex items-center gap-2">
        <div className="flex gap-1">
          <span className="w-1.5 h-1.5 bg-theme-interactive-primary rounded-full animate-bounce" style={{ animationDelay: '0ms' }} />
          <span className="w-1.5 h-1.5 bg-theme-interactive-primary rounded-full animate-bounce" style={{ animationDelay: '150ms' }} />
          <span className="w-1.5 h-1.5 bg-theme-interactive-primary rounded-full animate-bounce" style={{ animationDelay: '300ms' }} />
        </div>
        <span className="text-xs text-theme-text-tertiary">Thinking...</span>
      </div>
    ) : null;
  }

  return (
    <div>
      <div className="text-sm text-theme-primary prose prose-sm max-w-none prose-p:my-1 prose-headings:my-2 prose-pre:my-2 prose-code:text-xs">
        <ReactMarkdown>{safeContent}</ReactMarkdown>
        {isStreaming && (
          <span className="inline-block w-2 h-4 bg-theme-interactive-primary animate-pulse rounded-sm ml-0.5 align-text-bottom" />
        )}
      </div>

      {/* Streaming metadata */}
      {isStreaming && (tokenCount || elapsedMs) && (
        <div className="flex items-center gap-3 mt-1.5 pt-1 border-t border-theme/30">
          {tokenCount !== undefined && tokenCount > 0 && (
            <span className="flex items-center gap-1 text-[10px] text-theme-text-tertiary tabular-nums">
              <span className="inline-block w-1.5 h-1.5 bg-theme-interactive-primary rounded-full animate-pulse" />
              {tokenCount} tokens
            </span>
          )}
          {elapsedMs !== undefined && elapsedMs > 0 && (
            <span className="text-[10px] text-theme-text-tertiary tabular-nums">
              {(elapsedMs / 1000).toFixed(1)}s
            </span>
          )}
          {cost !== undefined && cost > 0 && (
            <span className="text-[10px] text-theme-text-tertiary tabular-nums">
              ${cost.toFixed(4)}
            </span>
          )}
        </div>
      )}
    </div>
  );
};

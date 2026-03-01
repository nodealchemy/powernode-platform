import React, { useEffect, useRef } from 'react';
import ReactMarkdown from 'react-markdown';
import { Loader2 } from 'lucide-react';
import { cn } from '@/shared/utils/cn';

interface StreamingMessageProps {
  content: string;
  isStreaming: boolean;
  tokenCount?: number;
  elapsedMs?: number;
  error?: string | null;
  showMetrics?: boolean;
  className?: string;
}

/**
 * StreamingMessage - Displays AI response content with real-time token streaming
 *
 * Features:
 * - Shows content as it streams in token by token
 * - Animated cursor indicator during streaming
 * - Markdown rendering for completed content
 * - Optional metrics display (tokens, elapsed time)
 */
export const StreamingMessage: React.FC<StreamingMessageProps> = ({
  content,
  isStreaming,
  tokenCount = 0,
  elapsedMs = 0,
  error,
  showMetrics = false,
  className,
}) => {
  const contentRef = useRef<HTMLDivElement>(null);

  // Auto-scroll to bottom as content streams
  useEffect(() => {
    if (contentRef.current && isStreaming) {
      contentRef.current.scrollTop = contentRef.current.scrollHeight;
    }
  }, [content, isStreaming]);

  if (error) {
    return (
      <div className={cn('rounded-lg p-4 bg-theme-danger/10 border border-theme-danger/30', className)}>
        <p className="text-theme-danger text-sm">{error}</p>
      </div>
    );
  }

  if (!content && isStreaming) {
    return (
      <div className={cn('flex items-center gap-2 p-4', className)}>
        <Loader2 className="h-4 w-4 animate-spin text-theme-muted" />
        <span className="text-sm text-theme-muted">AI is thinking...</span>
      </div>
    );
  }

  if (!content && !isStreaming) {
    return null;
  }

  return (
    <div className={cn('space-y-2', className)}>
      <div
        ref={contentRef}
        className="prose prose-sm dark:prose-invert max-w-none"
      >
        {isStreaming ? (
          // During streaming, show plain text with cursor
          <div className="whitespace-pre-wrap text-sm text-theme-primary">
            {content}
            <span className="inline-block w-2 h-4 ml-0.5 bg-theme-primary animate-pulse" />
          </div>
        ) : (
          // After streaming, render markdown
          <ReactMarkdown
            components={{
              h1: ({ children }) => <h1 className="text-2xl font-bold mb-4 mt-6">{children}</h1>,
              h2: ({ children }) => <h2 className="text-xl font-bold mb-3 mt-5">{children}</h2>,
              h3: ({ children }) => <h3 className="text-lg font-bold mb-2 mt-4">{children}</h3>,
              p: ({ children }) => <p className="mb-4 text-theme-primary">{children}</p>,
              ul: ({ children }) => <ul className="list-disc list-inside mb-4 ml-4">{children}</ul>,
              ol: ({ children }) => <ol className="list-decimal list-inside mb-4 ml-4">{children}</ol>,
              li: ({ children }) => <li className="mb-1">{children}</li>,
              pre: ({ children }) => (
                <pre className="bg-theme-surface p-4 rounded-lg overflow-x-auto mb-4 text-sm">
                  {children}
                </pre>
              ),
              code: ({ className, children }) => {
                const isInline = !className?.startsWith('language-');
                return isInline ? (
                  <code className="bg-theme-surface px-1.5 py-0.5 rounded text-sm font-mono">
                    {children}
                  </code>
                ) : (
                  <code className="font-mono text-sm">{children}</code>
                );
              },
              a: ({ href, children }) => (
                <a
                  href={href}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-theme-info hover:text-theme-info/80 underline"
                >
                  {children}
                </a>
              ),
              blockquote: ({ children }) => (
                <blockquote className="border-l-4 border-theme pl-4 italic mb-4">
                  {children}
                </blockquote>
              ),
            }}
          >
            {content}
          </ReactMarkdown>
        )}
      </div>

      {showMetrics && (
        <div className="flex items-center gap-4 text-xs text-theme-muted pt-2 border-t border-theme">
          {tokenCount > 0 && (
            <span>{tokenCount} tokens</span>
          )}
          {elapsedMs > 0 && (
            <span>{(elapsedMs / 1000).toFixed(1)}s</span>
          )}
          {isStreaming && (
            <span className="flex items-center gap-1">
              <Loader2 className="h-3 w-3 animate-spin" />
              Streaming...
            </span>
          )}
        </div>
      )}
    </div>
  );
};

export default StreamingMessage;

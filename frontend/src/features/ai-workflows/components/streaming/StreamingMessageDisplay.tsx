import React, { useState } from 'react';
import {
  Copy,
  CheckCircle2,
  ChevronDown,
  ChevronUp,
  Code,
  Terminal,
  FileJson,
  AlertCircle
} from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { useNotifications } from '@/shared/hooks/useNotifications';
import type { StreamingMessage } from './StreamingExecutionPanel';

interface StreamingMessageDisplayProps {
  message: StreamingMessage;
  showMetadata?: boolean;
  collapsible?: boolean;
  defaultExpanded?: boolean;
}

/**
 * StreamingMessageDisplay - Enhanced message display component
 *
 * Provides rich formatting and interaction capabilities for streaming messages:
 * - Syntax highlighting for code blocks
 * - Expandable/collapsible content
 * - Copy to clipboard functionality
 * - Metadata display with detailed information
 * - JSON formatting for structured data
 */
export const StreamingMessageDisplay: React.FC<StreamingMessageDisplayProps> = ({
  message,
  showMetadata = true,
  collapsible = false,
  defaultExpanded = true
}) => {
  const [expanded, setExpanded] = useState(defaultExpanded);
  const [copied, setCopied] = useState(false);
  const { addNotification } = useNotifications();

  const handleCopy = () => {
    navigator.clipboard.writeText(message.content);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);

    addNotification({
      type: 'success',
      title: 'Copied',
      message: 'Message copied to clipboard'
    });
  };

  const isJsonContent = () => {
    try {
      JSON.parse(message.content);
      return true;
    } catch {
      return false;
    }
  };

  const isCodeBlock = () => {
    return message.content.includes('```') || message.type === 'tool_result';
  };

  const formatJsonContent = () => {
    try {
      const parsed = JSON.parse(message.content);
      return JSON.stringify(parsed, null, 2);
    } catch {
      return message.content;
    }
  };

  interface CodePart {
    type: 'code';
    content: string;
    language: string;
  }

  interface TextPart {
    type: 'text';
    content: string;
  }

  type ContentPart = CodePart | TextPart;

  const extractCodeBlocks = (): ContentPart[] => {
    // eslint-disable-next-line security/detect-unsafe-regex -- This regex is safe: non-greedy match with literal delimiters
    const codeBlockRegex = /```(\w+)?\n([\s\S]*?)```/g;
    const parts: ContentPart[] = [];
    let lastIndex = 0;
    let match;

    while ((match = codeBlockRegex.exec(message.content)) !== null) {
      // Add text before code block
      if (match.index > lastIndex) {
        parts.push({
          type: 'text',
          content: message.content.slice(lastIndex, match.index)
        });
      }

      // Add code block
      parts.push({
        type: 'code',
        content: match[2],
        language: match[1] || 'text'
      });

      lastIndex = match.index + match[0].length;
    }

    // Add remaining text
    if (lastIndex < message.content.length) {
      parts.push({
        type: 'text',
        content: message.content.slice(lastIndex)
      });
    }

    return parts.length > 0 ? parts : [{ type: 'text', content: message.content }];
  };

  const renderContent = () => {
    if (isJsonContent() && message.type === 'tool_result') {
      return (
        <pre className="bg-theme-surface-hover p-3 rounded overflow-x-auto">
          <code className="text-sm text-theme-primary font-mono">
            {formatJsonContent()}
          </code>
        </pre>
      );
    }

    if (isCodeBlock()) {
      const parts = extractCodeBlocks();
      return (
        <div className="space-y-2">
          {parts.map((part, index) => (
            <div key={index}>
              {part.type === 'text' ? (
                <div className="text-theme-primary whitespace-pre-wrap break-words">
                  {part.content}
                </div>
              ) : (
                <div className="relative">
                  {part.type === 'code' && part.language && (
                    <div className="absolute top-2 right-2">
                      <Badge variant="outline" size="sm">
                        {part.language}
                      </Badge>
                    </div>
                  )}
                  <pre className="bg-theme-surface-hover p-4 rounded overflow-x-auto">
                    <code className="text-sm text-theme-primary font-mono">
                      {part.content}
                    </code>
                  </pre>
                </div>
              )}
            </div>
          ))}
        </div>
      );
    }

    return (
      <div className="text-theme-primary whitespace-pre-wrap break-words">
        {message.content}
      </div>
    );
  };

  const getContentIcon = () => {
    if (isJsonContent()) return <FileJson className="h-4 w-4" />;
    if (isCodeBlock()) return <Code className="h-4 w-4" />;
    if (message.type === 'tool_call') return <Terminal className="h-4 w-4" />;
    return null;
  };

  const renderMetadata = () => {
    if (!showMetadata || !message.metadata) return null;

    const metadataEntries = Object.entries(message.metadata).filter(
      ([_, value]) => value !== undefined && value !== null
    );

    if (metadataEntries.length === 0) return null;

    return (
      <div className="mt-3 pt-3 border-t border-theme">
        <div className="grid grid-cols-2 md:grid-cols-3 gap-2">
          {metadataEntries.map(([key, value]) => (
            <div key={key} className="text-xs">
              <span className="text-theme-tertiary">
                {key.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase())}:
              </span>{' '}
              <span className="text-theme-primary font-medium">
                {typeof value === 'number' && key.includes('cost')
                  ? `$${value.toFixed(4)}`
                  : typeof value === 'number' && key.includes('confidence')
                  ? `${(value * 100).toFixed(1)}%`
                  : String(value)}
              </span>
            </div>
          ))}
        </div>
      </div>
    );
  };

  return (
    <div className="border border-theme rounded-lg overflow-hidden">
      {/* Message Header */}
      <div className="bg-theme-surface px-4 py-2 flex items-center justify-between border-b border-theme">
        <div className="flex items-center gap-2">
          {getContentIcon()}
          <Badge variant="outline" size="sm">
            {message.type.replace('_', ' ')}
          </Badge>
          <span className="text-xs text-theme-tertiary">
            {new Date(message.timestamp).toLocaleTimeString()}
          </span>
          {message.metadata?.model && (
            <Badge variant="outline" size="sm">
              {message.metadata.model}
            </Badge>
          )}
        </div>

        <div className="flex items-center gap-1">
          <Button
            variant="ghost"
            size="sm"
            onClick={handleCopy}
            className="flex items-center gap-1"
          >
            {copied ? (
              <CheckCircle2 className="h-3 w-3 text-theme-success" />
            ) : (
              <Copy className="h-3 w-3" />
            )}
          </Button>
          {collapsible && (
            <Button
              variant="ghost"
              size="sm"
              onClick={() => setExpanded(!expanded)}
              className="flex items-center gap-1"
            >
              {expanded ? (
                <ChevronUp className="h-3 w-3" />
              ) : (
                <ChevronDown className="h-3 w-3" />
              )}
            </Button>
          )}
        </div>
      </div>

      {/* Message Content */}
      {expanded && (
        <div className="p-4">
          {message.type === 'error' && (
            <div className="flex items-start gap-2 mb-3 p-3 bg-theme-error bg-opacity-10 border border-theme-error rounded">
              <AlertCircle className="h-4 w-4 text-theme-error flex-shrink-0 mt-0.5" />
              <div className="text-sm text-theme-error">
                An error occurred during execution
              </div>
            </div>
          )}

          {renderContent()}
          {renderMetadata()}
        </div>
      )}
    </div>
  );
};

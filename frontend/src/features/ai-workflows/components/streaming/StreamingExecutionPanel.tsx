import React, { useState, useRef, useEffect } from 'react';
import {
  Loader2,
  Square,
  Play,
  Pause,
  RefreshCw,
  Download,
  Copy,
  CheckCircle2,
  AlertTriangle,
  Clock,
  Zap,
  MessageSquare
} from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { useNotifications } from '@/shared/hooks/useNotifications';

export interface StreamingMessage {
  id: string;
  type: 'text' | 'thought' | 'tool_call' | 'tool_result' | 'error' | 'system';
  content: string;
  timestamp: string;
  metadata?: {
    model?: string;
    tokens?: number;
    latency_ms?: number;
    tool_name?: string;
    confidence?: number;
  };
}

export interface StreamingExecutionState {
  run_id: string;
  workflow_id: string;
  workflow_name: string;
  status: 'initializing' | 'streaming' | 'paused' | 'completed' | 'failed' | 'cancelled';
  messages: StreamingMessage[];
  started_at: string;
  completed_at?: string;
  current_node?: {
    node_id: string;
    node_name: string;
    node_type: string;
  };
  metrics?: {
    total_tokens: number;
    total_cost: number;
    avg_latency_ms: number;
    message_count: number;
  };
}

interface StreamingExecutionPanelProps {
  executionState: StreamingExecutionState;
  onPause?: () => void;
  onResume?: () => void;
  onStop?: () => void;
  onRetry?: () => void;
  allowControls?: boolean;
  autoScroll?: boolean;
}

export const StreamingExecutionPanel: React.FC<StreamingExecutionPanelProps> = ({
  executionState,
  onPause,
  onResume,
  onStop,
  onRetry,
  allowControls = true,
  autoScroll = true
}) => {
  const [copied, setCopied] = useState(false);
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const { addNotification } = useNotifications();

  // Auto-scroll to bottom when new messages arrive
  useEffect(() => {
    if (autoScroll && messagesEndRef.current) {
      messagesEndRef.current.scrollIntoView({ behavior: 'smooth' });
    }
  }, [executionState.messages, autoScroll]);

  const getStatusBadge = () => {
    switch (executionState.status) {
      case 'initializing':
        return <Badge variant="outline" size="sm">Initializing</Badge>;
      case 'streaming':
        return <Badge variant="info" size="sm" className="animate-pulse">Streaming</Badge>;
      case 'paused':
        return <Badge variant="warning" size="sm">Paused</Badge>;
      case 'completed':
        return <Badge variant="success" size="sm">Completed</Badge>;
      case 'failed':
        return <Badge variant="danger" size="sm">Failed</Badge>;
      case 'cancelled':
        return <Badge variant="outline" size="sm">Cancelled</Badge>;
      default:
        return <Badge variant="outline" size="sm">{executionState.status}</Badge>;
    }
  };

  const getMessageIcon = (type: StreamingMessage['type']) => {
    switch (type) {
      case 'text':
        return <MessageSquare className="h-4 w-4 text-theme-primary" />;
      case 'thought':
        return <Zap className="h-4 w-4 text-theme-warning" />;
      case 'tool_call':
        return <Play className="h-4 w-4 text-theme-info" />;
      case 'tool_result':
        return <CheckCircle2 className="h-4 w-4 text-theme-success" />;
      case 'error':
        return <AlertTriangle className="h-4 w-4 text-theme-error" />;
      case 'system':
        return <Clock className="h-4 w-4 text-theme-tertiary" />;
      default:
        return <MessageSquare className="h-4 w-4 text-theme-tertiary" />;
    }
  };

  const getMessageStyles = (type: StreamingMessage['type']) => {
    switch (type) {
      case 'text':
        return 'bg-theme-surface border-theme-primary border-l-4';
      case 'thought':
        return 'bg-theme-warning bg-opacity-5 border-theme-warning border-l-4 italic';
      case 'tool_call':
        return 'bg-theme-info bg-opacity-5 border-theme-info border-l-4';
      case 'tool_result':
        return 'bg-theme-success bg-opacity-5 border-theme-success border-l-4';
      case 'error':
        return 'bg-theme-error bg-opacity-5 border-theme-error border-l-4';
      case 'system':
        return 'bg-theme-surface border-theme border-l-4 text-sm text-theme-tertiary';
      default:
        return 'bg-theme-surface border-theme border-l-4';
    }
  };

  const formatTimestamp = (timestamp: string) => {
    const date = new Date(timestamp);
    return date.toLocaleTimeString();
  };

  const handleCopyAll = () => {
    const allText = executionState.messages
      .map(msg => `[${formatTimestamp(msg.timestamp)}] ${msg.type.toUpperCase()}: ${msg.content}`)
      .join('\n\n');

    navigator.clipboard.writeText(allText);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);

    addNotification({
      type: 'success',
      title: 'Copied',
      message: 'All messages copied to clipboard'
    });
  };

  const handleDownload = () => {
    const data = {
      workflow_name: executionState.workflow_name,
      run_id: executionState.run_id,
      started_at: executionState.started_at,
      completed_at: executionState.completed_at,
      status: executionState.status,
      messages: executionState.messages,
      metrics: executionState.metrics
    };

    const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = `streaming-execution-${executionState.run_id}-${new Date().toISOString()}.json`;
    link.style.visibility = 'hidden';
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);

    addNotification({
      type: 'success',
      title: 'Downloaded',
      message: 'Execution log downloaded successfully'
    });
  };

  const canPause = executionState.status === 'streaming' && allowControls && onPause;
  const canResume = executionState.status === 'paused' && allowControls && onResume;
  const canStop = ['streaming', 'paused'].includes(executionState.status) && allowControls && onStop;
  const canRetry = ['completed', 'failed', 'cancelled'].includes(executionState.status) && allowControls && onRetry;

  const elapsedTime = () => {
    const start = new Date(executionState.started_at).getTime();
    const end = executionState.completed_at
      ? new Date(executionState.completed_at).getTime()
      : Date.now();
    const elapsed = end - start;
    const seconds = Math.floor(elapsed / 1000);
    const minutes = Math.floor(seconds / 60);
    const remainingSeconds = seconds % 60;
    return minutes > 0 ? `${minutes}m ${remainingSeconds}s` : `${seconds}s`;
  };

  return (
    <div className="space-y-4">
      {/* Header */}
      <Card className="p-4">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div>
              <h3 className="text-lg font-semibold text-theme-primary">
                {executionState.workflow_name}
              </h3>
              <p className="text-sm text-theme-tertiary">
                Run ID: {executionState.run_id.slice(0, 8)}...
              </p>
            </div>
            {getStatusBadge()}
          </div>

          {allowControls && (
            <div className="flex items-center gap-2">
              {canPause && (
                <Button
                  variant="outline"
                  size="sm"
                  onClick={onPause}
                  className="flex items-center gap-1"
                >
                  <Pause className="h-4 w-4" />
                  Pause
                </Button>
              )}
              {canResume && (
                <Button
                  variant="outline"
                  size="sm"
                  onClick={onResume}
                  className="flex items-center gap-1"
                >
                  <Play className="h-4 w-4" />
                  Resume
                </Button>
              )}
              {canStop && (
                <Button
                  variant="outline"
                  size="sm"
                  onClick={onStop}
                  className="flex items-center gap-1 text-theme-error hover:bg-theme-error hover:bg-opacity-10"
                >
                  <Square className="h-4 w-4" />
                  Stop
                </Button>
              )}
              {canRetry && (
                <Button
                  variant="outline"
                  size="sm"
                  onClick={onRetry}
                  className="flex items-center gap-1"
                >
                  <RefreshCw className="h-4 w-4" />
                  Retry
                </Button>
              )}
              <Button
                variant="outline"
                size="sm"
                onClick={handleCopyAll}
                className="flex items-center gap-1"
              >
                {copied ? (
                  <CheckCircle2 className="h-4 w-4 text-theme-success" />
                ) : (
                  <Copy className="h-4 w-4" />
                )}
                Copy
              </Button>
              <Button
                variant="outline"
                size="sm"
                onClick={handleDownload}
                className="flex items-center gap-1"
              >
                <Download className="h-4 w-4" />
                Export
              </Button>
            </div>
          )}
        </div>

        {/* Metrics Bar */}
        {executionState.metrics && (
          <div className="flex items-center gap-6 mt-4 pt-4 border-t border-theme text-sm text-theme-secondary">
            <span>
              Elapsed: <span className="font-medium text-theme-primary">{elapsedTime()}</span>
            </span>
            <span>
              Messages: <span className="font-medium text-theme-primary">{executionState.metrics.message_count}</span>
            </span>
            <span>
              Tokens: <span className="font-medium text-theme-primary">{executionState.metrics.total_tokens.toLocaleString()}</span>
            </span>
            <span>
              Cost: <span className="font-medium text-theme-primary">${executionState.metrics.total_cost.toFixed(4)}</span>
            </span>
            <span>
              Avg Latency: <span className="font-medium text-theme-primary">{executionState.metrics.avg_latency_ms}ms</span>
            </span>
          </div>
        )}

        {/* Current Node */}
        {executionState.current_node && (
          <div className="flex items-center gap-2 mt-4 pt-4 border-t border-theme">
            <Loader2 className="h-4 w-4 animate-spin text-theme-interactive-primary" />
            <span className="text-sm text-theme-secondary">
              Executing: <span className="font-medium text-theme-primary">{executionState.current_node.node_name}</span>
              <span className="text-theme-tertiary ml-2">({executionState.current_node.node_type})</span>
            </span>
          </div>
        )}
      </Card>

      {/* Messages Stream */}
      <Card className="p-4">
        <div
          ref={containerRef}
          className="space-y-3 max-h-[600px] overflow-y-auto"
        >
          {executionState.messages.length === 0 ? (
            <div className="text-center py-12 text-theme-tertiary">
              <Loader2 className="h-8 w-8 animate-spin mx-auto mb-2" />
              <p>Waiting for streaming execution to start...</p>
            </div>
          ) : (
            executionState.messages.map((message) => (
              <div
                key={message.id}
                className={`p-4 rounded-lg ${getMessageStyles(message.type)}`}
              >
                <div className="flex items-start gap-3">
                  <div className="flex-shrink-0 mt-1">
                    {getMessageIcon(message.type)}
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center justify-between mb-2">
                      <Badge variant="outline" size="sm">
                        {message.type.replace('_', ' ')}
                      </Badge>
                      <span className="text-xs text-theme-tertiary">
                        {formatTimestamp(message.timestamp)}
                      </span>
                    </div>
                    <div className="text-theme-primary whitespace-pre-wrap break-words">
                      {message.content}
                    </div>
                    {message.metadata && (
                      <div className="flex items-center gap-4 mt-2 text-xs text-theme-tertiary">
                        {message.metadata.model && (
                          <span>Model: {message.metadata.model}</span>
                        )}
                        {message.metadata.tokens && (
                          <span>Tokens: {message.metadata.tokens}</span>
                        )}
                        {message.metadata.latency_ms && (
                          <span>Latency: {message.metadata.latency_ms}ms</span>
                        )}
                        {message.metadata.tool_name && (
                          <span>Tool: {message.metadata.tool_name}</span>
                        )}
                        {message.metadata.confidence !== undefined && (
                          <span>Confidence: {(message.metadata.confidence * 100).toFixed(1)}%</span>
                        )}
                      </div>
                    )}
                  </div>
                </div>
              </div>
            ))
          )}
          <div ref={messagesEndRef} />
        </div>

        {/* Streaming Indicator */}
        {executionState.status === 'streaming' && (
          <div className="flex items-center justify-center gap-2 mt-4 pt-4 border-t border-theme text-sm text-theme-secondary">
            <div className="flex gap-1">
              <div className="w-2 h-2 bg-theme-interactive-primary rounded-full animate-bounce" style={{ animationDelay: '0ms' }} />
              <div className="w-2 h-2 bg-theme-interactive-primary rounded-full animate-bounce" style={{ animationDelay: '150ms' }} />
              <div className="w-2 h-2 bg-theme-interactive-primary rounded-full animate-bounce" style={{ animationDelay: '300ms' }} />
            </div>
            <span>Streaming in progress...</span>
          </div>
        )}
      </Card>
    </div>
  );
};

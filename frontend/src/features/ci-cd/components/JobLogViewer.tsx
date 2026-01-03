import React, { useState, useEffect, useRef, useCallback } from 'react';
import { Download, Copy, Check, ArrowDown, Loader2, Wifi, WifiOff } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { gitProvidersApi } from '@/features/git-providers/services/gitProvidersApi';
import { useNotification } from '@/shared/hooks/useNotification';
import { useJobLogsWebSocket } from '../hooks/useJobLogsWebSocket';

interface JobLogViewerProps {
  repositoryId: string;
  pipelineId: string;
  jobId: string;
  jobName?: string;
  isJobRunning?: boolean;
}

// Simple ANSI to HTML converter for common codes - using theme-compatible classes
const ansiToHtml = (text: string): string => {
  const ansiCodes: Record<string, string> = {
    '0': '</span>',
    '1': '<span class="font-bold">',
    '30': '<span class="text-theme-primary">',
    '31': '<span class="text-theme-error">',
    '32': '<span class="text-theme-success">',
    '33': '<span class="text-theme-warning">',
    '34': '<span class="text-theme-info">',
    '35': '<span class="text-theme-accent">',
    '36': '<span class="text-theme-info">',
    '37': '<span class="text-theme-tertiary">',
    '90': '<span class="text-theme-secondary">',
    '91': '<span class="text-theme-error">',
    '92': '<span class="text-theme-success">',
    '93': '<span class="text-theme-warning">',
    '94': '<span class="text-theme-info">',
    '95': '<span class="text-theme-accent">',
    '96': '<span class="text-theme-info">',
  };

  const result = text
    // eslint-disable-next-line no-control-regex
    .replace(/\x1b\[(\d+)m/g, (_, code) => ansiCodes[code] || '')
    // eslint-disable-next-line no-control-regex
    .replace(/\x1b\[\d+;\d+m/g, '') // Remove unsupported compound codes
    // eslint-disable-next-line no-control-regex
    .replace(/\x1b\[K/g, ''); // Remove clear line codes

  return result;
};

export const JobLogViewer: React.FC<JobLogViewerProps> = ({
  repositoryId,
  pipelineId,
  jobId,
  jobName,
  isJobRunning = false,
}) => {
  // WebSocket connection for streaming
  const {
    logs: wsLogs,
    isComplete: wsIsComplete,
    isStreaming,
    isConnected,
    error: wsError,
    bytesReceived,
    connectionMethod,
    refresh: wsRefresh,
  } = useJobLogsWebSocket({
    repositoryId,
    pipelineId,
    jobId,
    enabled: true,
  });

  // Polling fallback state
  const [pollingLogs, setPollingLogs] = useState<string>('');
  const [pollingLoading, setPollingLoading] = useState(false);
  const [pollingError, setPollingError] = useState<string | null>(null);
  const [usePolling, setUsePolling] = useState(false);

  // UI state
  const [autoScroll, setAutoScroll] = useState(true);
  const [copied, setCopied] = useState(false);
  const logContainerRef = useRef<HTMLDivElement>(null);
  const { showNotification } = useNotification();

  // Determine which logs to display
  const logs = usePolling ? pollingLogs : wsLogs;
  const loading = usePolling ? pollingLoading : (!isConnected && !wsLogs);
  const error = usePolling ? pollingError : wsError;
  const isComplete = usePolling ? !isJobRunning : wsIsComplete;

  // Fallback to polling if WebSocket fails
  useEffect(() => {
    if (connectionMethod === 'disconnected' && !isConnected && !usePolling) {
      // Wait a bit before falling back to polling
      const timeout = setTimeout(() => {
        if (connectionMethod === 'disconnected') {
          setUsePolling(true);
        }
      }, 3000);

      return () => clearTimeout(timeout);
    }
  }, [connectionMethod, isConnected, usePolling]);

  // Polling logic
  const fetchLogs = useCallback(async () => {
    if (!usePolling) return;

    try {
      setPollingError(null);
      const data = await gitProvidersApi.getJobLogs(repositoryId, pipelineId, jobId);
      setPollingLogs(data.logs || '');
    } catch (err) {
      setPollingError(err instanceof Error ? err.message : 'Failed to fetch logs');
    } finally {
      setPollingLoading(false);
    }
  }, [repositoryId, pipelineId, jobId, usePolling]);

  useEffect(() => {
    if (!usePolling) return;

    setPollingLoading(true);
    fetchLogs();

    // Poll for updates if job is running
    let pollInterval: NodeJS.Timeout | null = null;
    if (isJobRunning) {
      pollInterval = setInterval(fetchLogs, 5000);
    }

    return () => {
      if (pollInterval) {
        clearInterval(pollInterval);
      }
    };
  }, [fetchLogs, isJobRunning, usePolling]);

  // Auto-scroll effect
  useEffect(() => {
    if (autoScroll && logContainerRef.current) {
      logContainerRef.current.scrollTop = logContainerRef.current.scrollHeight;
    }
  }, [logs, autoScroll]);

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(logs);
      setCopied(true);
      showNotification('Logs copied to clipboard', 'success');
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // Copy failed silently
    }
  };

  const handleDownload = () => {
    const blob = new Blob([logs], { type: 'text/plain' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `${jobName || 'job'}-logs.txt`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  };

  const handleRefresh = () => {
    if (usePolling) {
      fetchLogs();
    } else {
      wsRefresh();
    }
  };

  const logLines = logs.split('\n');

  if (loading && !logs) {
    return (
      <div className="bg-theme-surface-inset rounded-lg p-4 h-96 flex items-center justify-center">
        <div className="text-center">
          <Loader2 className="w-6 h-6 text-theme-secondary animate-spin mx-auto mb-2" />
          <p className="text-sm text-theme-tertiary">
            {usePolling ? 'Loading logs...' : 'Connecting to log stream...'}
          </p>
        </div>
      </div>
    );
  }

  if (error && !logs) {
    return (
      <div className="bg-theme-surface-inset rounded-lg p-4 h-96 flex items-center justify-center">
        <div className="text-center">
          <p className="text-theme-error mb-2">{error}</p>
          <Button onClick={handleRefresh} variant="secondary" size="sm">
            Try Again
          </Button>
        </div>
      </div>
    );
  }

  return (
    <div className="bg-theme-surface-inset rounded-lg overflow-hidden">
      {/* Header */}
      <div className="flex items-center justify-between px-4 py-2 bg-theme-surface border-b border-theme">
        <div className="flex items-center gap-2">
          <span className="text-sm text-theme-secondary">{jobName || 'Job Logs'}</span>
          {isStreaming && (
            <span className="flex items-center gap-1 text-xs text-theme-success">
              <span className="w-2 h-2 bg-theme-success rounded-full animate-pulse" />
              Live
            </span>
          )}
          {isJobRunning && !isStreaming && usePolling && (
            <span className="flex items-center gap-1 text-xs text-theme-warning">
              <span className="w-2 h-2 bg-theme-warning rounded-full animate-pulse" />
              Polling
            </span>
          )}
        </div>
        <div className="flex items-center gap-2">
          {/* Connection status indicator */}
          <div
            className={`flex items-center gap-1 text-xs ${
              isConnected ? 'text-theme-success' : usePolling ? 'text-theme-warning' : 'text-theme-tertiary'
            }`}
            title={
              isConnected
                ? 'Connected via WebSocket'
                : usePolling
                ? 'Using HTTP polling'
                : 'Disconnected'
            }
          >
            {isConnected ? (
              <Wifi className="w-3 h-3" />
            ) : (
              <WifiOff className="w-3 h-3" />
            )}
          </div>
          <Button
            onClick={() => setAutoScroll(!autoScroll)}
            variant="ghost"
            size="sm"
            className={`text-theme-secondary hover:text-theme-primary ${autoScroll ? 'text-theme-success' : ''}`}
            title={autoScroll ? 'Auto-scroll enabled' : 'Auto-scroll disabled'}
          >
            <ArrowDown className="w-4 h-4" />
          </Button>
          <Button
            onClick={handleCopy}
            variant="ghost"
            size="sm"
            className="text-theme-secondary hover:text-theme-primary"
            title="Copy logs"
          >
            {copied ? <Check className="w-4 h-4" /> : <Copy className="w-4 h-4" />}
          </Button>
          <Button
            onClick={handleDownload}
            variant="ghost"
            size="sm"
            className="text-theme-secondary hover:text-theme-primary"
            title="Download logs"
          >
            <Download className="w-4 h-4" />
          </Button>
        </div>
      </div>

      {/* Log Content */}
      <div
        ref={logContainerRef}
        className="h-96 overflow-auto font-mono text-sm bg-theme-surface-inset"
        onScroll={(e) => {
          const target = e.target as HTMLDivElement;
          const isAtBottom = target.scrollHeight - target.scrollTop - target.clientHeight < 50;
          if (!isAtBottom && autoScroll) {
            setAutoScroll(false);
          }
        }}
      >
        {logs ? (
          <table className="w-full">
            <tbody>
              {logLines.map((line, index) => (
                <tr key={index} className="hover:bg-theme-surface-hover">
                  <td className="px-3 py-0.5 text-theme-tertiary select-none text-right align-top w-12 border-r border-theme">
                    {index + 1}
                  </td>
                  <td
                    className="px-3 py-0.5 text-theme-primary whitespace-pre-wrap break-all"
                    dangerouslySetInnerHTML={{ __html: ansiToHtml(line) }}
                  />
                </tr>
              ))}
            </tbody>
          </table>
        ) : (
          <div className="flex items-center justify-center h-full text-theme-tertiary">
            No logs available
          </div>
        )}
      </div>

      {/* Footer */}
      <div className="flex items-center justify-between px-4 py-2 bg-theme-surface border-t border-theme text-xs text-theme-tertiary">
        <span>
          {logLines.length} lines • {(logs.length / 1024).toFixed(1)} KB
        </span>
        {!usePolling && bytesReceived > 0 && (
          <span>
            Streamed: {(bytesReceived / 1024).toFixed(1)} KB
          </span>
        )}
        {isComplete && (
          <span className="text-theme-success">Complete</span>
        )}
      </div>
    </div>
  );
};

export default JobLogViewer;

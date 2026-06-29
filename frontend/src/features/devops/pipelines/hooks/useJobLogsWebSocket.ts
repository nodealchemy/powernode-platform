import { useState, useEffect, useRef, useCallback } from 'react';
import { useWebSocket } from '@/shared/hooks/useWebSocket';

interface LogChunk {
  content: string;
  offset: number;
  is_complete: boolean;
  chunk_size: number;
}

// Inner payload routed by the WebSocket singleton (the `message` field of an
// ActionCable frame). Subscription confirm/reject/ping frames are handled inside
// the manager; consumers only ever receive this application payload.
interface JobLogMessage {
  type: string;
  job_id: string;
  payload?: LogChunk | { error: string } | { status: string; conclusion?: string };
  timestamp: string;
}

interface UseJobLogsWebSocketResult {
  logs: string;
  isComplete: boolean;
  isStreaming: boolean;
  isConnected: boolean;
  error: string | null;
  bytesReceived: number;
  connectionMethod: 'websocket' | 'polling' | 'disconnected';
  refresh: () => void;
}

interface UseJobLogsWebSocketParams {
  repositoryId: string;
  pipelineId: string;
  jobId: string;
  enabled?: boolean;
}

const CHANNEL = 'GitJobLogsChannel';

export function useJobLogsWebSocket({
  repositoryId,
  pipelineId,
  jobId,
  enabled = true,
}: UseJobLogsWebSocketParams): UseJobLogsWebSocketResult {
  const { isConnected: wsConnected, subscribe, sendMessage } = useWebSocket();

  const [logs, setLogs] = useState<string>('');
  const [isComplete, setIsComplete] = useState(false);
  const [isStreaming, setIsStreaming] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [bytesReceived, setBytesReceived] = useState(0);
  const [connectionMethod, setConnectionMethod] = useState<'websocket' | 'polling' | 'disconnected'>('disconnected');

  const logsBufferRef = useRef<Map<number, string>>(new Map());
  const lastProcessedOffsetRef = useRef(0);

  const channelParams = { repository_id: repositoryId, pipeline_id: pipelineId, job_id: jobId };

  const processBufferedChunks = useCallback(() => {
    const buffer = logsBufferRef.current;
    let currentOffset = lastProcessedOffsetRef.current;
    let newContent = '';

    while (buffer.has(currentOffset)) {
      const chunk = buffer.get(currentOffset)!;
      newContent += chunk;
      buffer.delete(currentOffset);
      currentOffset += chunk.length;
    }

    if (newContent) {
      lastProcessedOffsetRef.current = currentOffset;
      setLogs(prev => prev + newContent);
      setBytesReceived(currentOffset);
    }
  }, []);

  const handleMessage = useCallback((message: JobLogMessage) => {
    const { type, payload } = message;

    switch (type) {
      case 'connection_established':
        setIsStreaming(true);
        break;

      case 'log.chunk':
      case 'log.complete': {
        const logPayload = payload as LogChunk;

        if (logPayload.offset === 0) {
          setLogs(logPayload.content);
          lastProcessedOffsetRef.current = logPayload.content.length;
          setBytesReceived(logPayload.content.length);
          logsBufferRef.current.clear();
        } else {
          logsBufferRef.current.set(logPayload.offset, logPayload.content);
          processBufferedChunks();
        }

        if (logPayload.is_complete) {
          setIsComplete(true);
          setIsStreaming(false);
        }
        break;
      }

      case 'log.error': {
        const errorPayload = payload as { error: string };
        setError(errorPayload.error);
        setIsStreaming(false);
        break;
      }

      case 'job.status': {
        const statusPayload = payload as { status: string; conclusion?: string };
        if (statusPayload.status !== 'running') {
          setIsStreaming(false);
        }
        break;
      }
    }
  }, [processBufferedChunks]);

  // Subscribe through the shared WebSocket singleton. The manager owns the
  // single app-wide connection (with the canonical Redux-backed token) and
  // automatic reconnection/resubscription, so this hook no longer opens a raw
  // socket or manages its own backoff.
  useEffect(() => {
    if (!enabled || !jobId) {
      setConnectionMethod('disconnected');
      return;
    }

    if (!wsConnected) {
      // Surfaces as connectionMethod === 'disconnected' so JobLogViewer can fall
      // back to polling if the connection never comes up.
      setConnectionMethod('disconnected');
      return;
    }

    const unsubscribe = subscribe({
      channel: CHANNEL,
      params: channelParams,
      onMessage: (data) => handleMessage(data as JobLogMessage),
      onError: (err) => {
        setError(err);
        setConnectionMethod('disconnected');
      },
    });

    setConnectionMethod('websocket');
    setIsStreaming(true);

    return () => {
      unsubscribe();
      setIsStreaming(false);
    };
    // channelParams is derived from repositoryId/pipelineId/jobId.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [enabled, jobId, repositoryId, pipelineId, wsConnected, subscribe, handleMessage]);

  const refresh = useCallback(() => {
    setLogs('');
    setIsComplete(false);
    setError(null);
    setBytesReceived(0);
    logsBufferRef.current.clear();
    lastProcessedOffsetRef.current = 0;

    // Ask the server to replay from offset 0 over the existing subscription.
    // If the socket is momentarily down sendMessage is a no-op; the manager
    // resubscribes on reconnect and the server resends from offset 0.
    void sendMessage(CHANNEL, 'refresh', undefined, channelParams);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [repositoryId, pipelineId, jobId, sendMessage]);

  return {
    logs,
    isComplete,
    isStreaming,
    isConnected: wsConnected && enabled && !!jobId,
    error,
    bytesReceived,
    connectionMethod,
    refresh,
  };
}

export default useJobLogsWebSocket;

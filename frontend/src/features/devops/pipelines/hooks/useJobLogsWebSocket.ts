import { useState, useEffect, useRef, useCallback } from 'react';

interface LogChunk {
  content: string;
  offset: number;
  is_complete: boolean;
  chunk_size: number;
}

interface WebSocketMessage {
  type?: string;
  identifier?: string;
  message?: {
    type: string;
    job_id: string;
    payload?: LogChunk | { error: string } | { status: string; conclusion?: string };
    timestamp: string;
  };
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

export function useJobLogsWebSocket({
  repositoryId,
  pipelineId,
  jobId,
  enabled = true,
}: UseJobLogsWebSocketParams): UseJobLogsWebSocketResult {
  const [logs, setLogs] = useState<string>('');
  const [isComplete, setIsComplete] = useState(false);
  const [isStreaming, setIsStreaming] = useState(false);
  const [isConnected, setIsConnected] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [bytesReceived, setBytesReceived] = useState(0);
  const [connectionMethod, setConnectionMethod] = useState<'websocket' | 'polling' | 'disconnected'>('disconnected');

  const wsRef = useRef<WebSocket | null>(null);
  const reconnectAttemptsRef = useRef(0);
  const maxReconnectAttempts = 3;
  const logsBufferRef = useRef<Map<number, string>>(new Map());
  const lastProcessedOffsetRef = useRef(0);

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

  const handleMessage = useCallback((data: WebSocketMessage) => {
    if (data.type === 'ping') {
      return;
    }

    if (data.type === 'confirm_subscription') {
      setIsConnected(true);
      setConnectionMethod('websocket');
      setIsStreaming(true);
      return;
    }

    if (data.type === 'reject_subscription') {
      setError('Subscription rejected - access denied');
      setConnectionMethod('disconnected');
      return;
    }

    if (data.message) {
      const { type, payload } = data.message;

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
    }
  }, [processBufferedChunks]);

  const connect = useCallback(() => {
    if (!enabled || !jobId) return;

    const token = localStorage.getItem('access_token') || sessionStorage.getItem('access_token');

    if (!token) {
      setError('Authentication required');
      setConnectionMethod('disconnected');
      return;
    }

    try {
      const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
      const host = window.location.host;
      const timestamp = Date.now();
      const wsUrl = `${protocol}//${host}/cable?token=${encodeURIComponent(token)}&t=${timestamp}`;

      wsRef.current = new WebSocket(wsUrl);

      wsRef.current.onopen = () => {
        reconnectAttemptsRef.current = 0;

        const identifier = JSON.stringify({
          channel: 'GitJobLogsChannel',
          repository_id: repositoryId,
          pipeline_id: pipelineId,
          job_id: jobId,
        });

        wsRef.current?.send(JSON.stringify({
          command: 'subscribe',
          identifier,
        }));
      };

      wsRef.current.onmessage = (event) => {
        try {
          const data = JSON.parse(event.data);
          handleMessage(data);
        } catch {
          // Ignore parse errors
        }
      };

      wsRef.current.onclose = () => {
        setIsConnected(false);

        if (reconnectAttemptsRef.current < maxReconnectAttempts && enabled) {
          reconnectAttemptsRef.current++;
          const delay = Math.min(1000 * Math.pow(2, reconnectAttemptsRef.current), 10000);
          setTimeout(connect, delay);
        } else {
          setConnectionMethod('disconnected');
        }
      };

      wsRef.current.onerror = () => {
        setConnectionMethod('disconnected');
      };

    } catch {
      setConnectionMethod('disconnected');
    }
  }, [enabled, jobId, repositoryId, pipelineId, handleMessage]);

  const disconnect = useCallback(() => {
    if (wsRef.current) {
      const identifier = JSON.stringify({
        channel: 'GitJobLogsChannel',
        repository_id: repositoryId,
        pipeline_id: pipelineId,
        job_id: jobId,
      });

      if (wsRef.current.readyState === WebSocket.OPEN) {
        wsRef.current.send(JSON.stringify({
          command: 'unsubscribe',
          identifier,
        }));
      }

      wsRef.current.close(1000, 'Component unmounted');
      wsRef.current = null;
    }
    setIsConnected(false);
    setIsStreaming(false);
  }, [repositoryId, pipelineId, jobId]);

  const refresh = useCallback(() => {
    setLogs('');
    setIsComplete(false);
    setError(null);
    setBytesReceived(0);
    logsBufferRef.current.clear();
    lastProcessedOffsetRef.current = 0;

    if (wsRef.current?.readyState === WebSocket.OPEN) {
      const identifier = JSON.stringify({
        channel: 'GitJobLogsChannel',
        repository_id: repositoryId,
        pipeline_id: pipelineId,
        job_id: jobId,
      });

      wsRef.current.send(JSON.stringify({
        command: 'message',
        identifier,
        data: JSON.stringify({ action: 'refresh' }),
      }));
    } else {
      disconnect();
      connect();
    }
  }, [repositoryId, pipelineId, jobId, disconnect, connect]);

  useEffect(() => {
    if (enabled && jobId) {
      connect();
    }

    return () => {
      disconnect();
    };
  }, [enabled, jobId, connect, disconnect]);

  return {
    logs,
    isComplete,
    isStreaming,
    isConnected,
    error,
    bytesReceived,
    connectionMethod,
    refresh,
  };
}

export default useJobLogsWebSocket;

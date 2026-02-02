import { useCallback, useRef, useEffect, useState } from 'react';
import { useWebSocket } from './useWebSocket';

// Streaming event types
export type StreamEventType = 'stream_start' | 'token' | 'stream_end' | 'stream_error';

// Stream start event
export interface StreamStartEvent {
  type: 'stream_start';
  data: {
    stream_id: string;
    agent_id?: string;
    conversation_id?: string;
    execution_id?: string;
  };
  timestamp: string;
}

// Token event (individual token/chunk)
export interface TokenEvent {
  type: 'token';
  data: {
    stream_id: string;
    content: string;
    accumulated_content: string;
    chunk_index: number;
  };
  timestamp: string;
}

// Stream end event
export interface StreamEndEvent {
  type: 'stream_end';
  data: {
    stream_id: string;
    content: string;
    usage: {
      prompt_tokens?: number;
      completion_tokens?: number;
      total_tokens?: number;
    };
    cost: number;
    duration_ms: number;
  };
  timestamp: string;
}

// Stream error event
export interface StreamErrorEvent {
  type: 'stream_error';
  data: {
    stream_id: string;
    error: string;
    partial_content?: string;
  };
  timestamp: string;
}

export type StreamEvent = StreamStartEvent | TokenEvent | StreamEndEvent | StreamErrorEvent;

// Streaming state
export interface StreamingState {
  isStreaming: boolean;
  streamId: string | null;
  content: string;
  tokens: string[];
  tokenCount: number;
  startTime: number | null;
  elapsedMs: number;
  error: string | null;
  usage: {
    prompt_tokens: number;
    completion_tokens: number;
    total_tokens: number;
  } | null;
  cost: number;
}

// Hook options
interface UseAiStreamingWebSocketOptions {
  executionId?: string;
  conversationId?: string;
  onStreamStart?: (event: StreamStartEvent) => void;
  onToken?: (event: TokenEvent) => void;
  onStreamEnd?: (event: StreamEndEvent) => void;
  onStreamError?: (event: StreamErrorEvent) => void;
  onError?: (error: string) => void;
}

const initialState: StreamingState = {
  isStreaming: false,
  streamId: null,
  content: '',
  tokens: [],
  tokenCount: 0,
  startTime: null,
  elapsedMs: 0,
  error: null,
  usage: null,
  cost: 0,
};

export const useAiStreamingWebSocket = ({
  executionId,
  conversationId,
  onStreamStart,
  onToken,
  onStreamEnd,
  onStreamError,
  onError,
}: UseAiStreamingWebSocketOptions) => {
  const { isConnected, subscribe, error: connectionError } = useWebSocket();
  const [state, setState] = useState<StreamingState>(initialState);
  const unsubscribeRef = useRef<(() => void) | null>(null);
  const elapsedIntervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  // Store callback refs
  const onStreamStartRef = useRef(onStreamStart);
  const onTokenRef = useRef(onToken);
  const onStreamEndRef = useRef(onStreamEnd);
  const onStreamErrorRef = useRef(onStreamError);
  const onErrorRef = useRef(onError);

  onStreamStartRef.current = onStreamStart;
  onTokenRef.current = onToken;
  onStreamEndRef.current = onStreamEnd;
  onStreamErrorRef.current = onStreamError;
  onErrorRef.current = onError;

  // Update elapsed time during streaming
  useEffect(() => {
    if (state.isStreaming && state.startTime) {
      elapsedIntervalRef.current = setInterval(() => {
        setState(prev => ({
          ...prev,
          elapsedMs: Date.now() - (prev.startTime || Date.now()),
        }));
      }, 100);

      return () => {
        if (elapsedIntervalRef.current) {
          clearInterval(elapsedIntervalRef.current);
        }
      };
    }
  }, [state.isStreaming, state.startTime]);

  // Handle incoming messages
  const handleMessage = useCallback((data: unknown) => {
    const event = data as StreamEvent;

    if (!event?.type) return;

    switch (event.type) {
      case 'stream_start':
        setState({
          isStreaming: true,
          streamId: event.data.stream_id,
          content: '',
          tokens: [],
          tokenCount: 0,
          startTime: Date.now(),
          elapsedMs: 0,
          error: null,
          usage: null,
          cost: 0,
        });
        onStreamStartRef.current?.(event);
        break;

      case 'token':
        setState(prev => ({
          ...prev,
          content: event.data.accumulated_content,
          tokens: [...prev.tokens, event.data.content],
          tokenCount: event.data.chunk_index + 1,
        }));
        onTokenRef.current?.(event);
        break;

      case 'stream_end':
        if (elapsedIntervalRef.current) {
          clearInterval(elapsedIntervalRef.current);
        }
        setState(prev => ({
          ...prev,
          isStreaming: false,
          content: event.data.content,
          elapsedMs: event.data.duration_ms,
          usage: {
            prompt_tokens: event.data.usage?.prompt_tokens || 0,
            completion_tokens: event.data.usage?.completion_tokens || 0,
            total_tokens: event.data.usage?.total_tokens || 0,
          },
          cost: event.data.cost,
        }));
        onStreamEndRef.current?.(event);
        break;

      case 'stream_error':
        if (elapsedIntervalRef.current) {
          clearInterval(elapsedIntervalRef.current);
        }
        setState(prev => ({
          ...prev,
          isStreaming: false,
          error: event.data.error,
          content: event.data.partial_content || prev.content,
        }));
        onStreamErrorRef.current?.(event);
        break;

      case 'subscription.confirmed' as StreamEventType:
        // Ignore subscription confirmation
        break;

      default:
        // Unknown event type - ignored
        break;
    }
  }, []);

  // Subscribe to streaming channel
  useEffect(() => {
    if (!isConnected) return;
    if (!executionId && !conversationId) return;

    const params: Record<string, string> = {};
    if (executionId) params.execution_id = executionId;
    if (conversationId) params.conversation_id = conversationId;

    unsubscribeRef.current = subscribe({
      channel: 'AiStreamingChannel',
      params,
      onMessage: handleMessage,
      onError: (err) => onErrorRef.current?.(err),
    });

    return () => {
      if (unsubscribeRef.current) {
        unsubscribeRef.current();
        unsubscribeRef.current = null;
      }
      if (elapsedIntervalRef.current) {
        clearInterval(elapsedIntervalRef.current);
      }
    };
  }, [isConnected, executionId, conversationId, subscribe, handleMessage]);

  // Handle connection errors
  useEffect(() => {
    if (connectionError) {
      onErrorRef.current?.(connectionError);
    }
  }, [connectionError]);

  // Reset state
  const reset = useCallback(() => {
    if (elapsedIntervalRef.current) {
      clearInterval(elapsedIntervalRef.current);
    }
    setState(initialState);
  }, []);

  return {
    ...state,
    isConnected,
    reset,
    error: connectionError || state.error,
  };
};

export default useAiStreamingWebSocket;

import { renderHook, act } from '@testing-library/react';
import { useAiStreamingWebSocket } from './useAiStreamingWebSocket';

// Mock useWebSocket hook
const mockSubscribe = jest.fn();
const mockUnsubscribe = jest.fn();

jest.mock('./useWebSocket', () => ({
  useWebSocket: () => ({
    isConnected: true,
    subscribe: mockSubscribe,
    error: null,
  }),
}));

describe('useAiStreamingWebSocket', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockSubscribe.mockReturnValue(mockUnsubscribe);
  });

  describe('initialization', () => {
    it('returns initial state', () => {
      const { result } = renderHook(() =>
        useAiStreamingWebSocket({ executionId: 'exec-123' })
      );

      expect(result.current.isStreaming).toBe(false);
      expect(result.current.streamId).toBeNull();
      expect(result.current.content).toBe('');
      expect(result.current.tokens).toEqual([]);
      expect(result.current.tokenCount).toBe(0);
      expect(result.current.error).toBeNull();
    });

    it('subscribes to channel with execution_id', () => {
      renderHook(() =>
        useAiStreamingWebSocket({ executionId: 'exec-123' })
      );

      expect(mockSubscribe).toHaveBeenCalledWith({
        channel: 'AiStreamingChannel',
        params: { execution_id: 'exec-123' },
        onMessage: expect.any(Function),
        onError: expect.any(Function),
      });
    });

    it('subscribes to channel with conversation_id', () => {
      renderHook(() =>
        useAiStreamingWebSocket({ conversationId: 'conv-456' })
      );

      expect(mockSubscribe).toHaveBeenCalledWith({
        channel: 'AiStreamingChannel',
        params: { conversation_id: 'conv-456' },
        onMessage: expect.any(Function),
        onError: expect.any(Function),
      });
    });

    it('does not subscribe without execution or conversation id', () => {
      renderHook(() => useAiStreamingWebSocket({}));

      expect(mockSubscribe).not.toHaveBeenCalled();
    });
  });

  describe('stream_start event', () => {
    it('updates state on stream start', () => {
      const onStreamStart = jest.fn();
      const { result } = renderHook(() =>
        useAiStreamingWebSocket({
          executionId: 'exec-123',
          onStreamStart,
        })
      );

      // Get the onMessage callback
      const onMessage = mockSubscribe.mock.calls[0][0].onMessage;

      act(() => {
        onMessage({
          type: 'stream_start',
          data: { stream_id: 'stream-abc' },
          timestamp: '2026-01-30T10:00:00Z',
        });
      });

      expect(result.current.isStreaming).toBe(true);
      expect(result.current.streamId).toBe('stream-abc');
      expect(result.current.startTime).not.toBeNull();
      expect(onStreamStart).toHaveBeenCalled();
    });
  });

  describe('token event', () => {
    it('accumulates tokens and content', () => {
      const onToken = jest.fn();
      const { result } = renderHook(() =>
        useAiStreamingWebSocket({
          executionId: 'exec-123',
          onToken,
        })
      );

      const onMessage = mockSubscribe.mock.calls[0][0].onMessage;

      // Start stream
      act(() => {
        onMessage({
          type: 'stream_start',
          data: { stream_id: 'stream-abc' },
          timestamp: '2026-01-30T10:00:00Z',
        });
      });

      // Receive tokens
      act(() => {
        onMessage({
          type: 'token',
          data: {
            stream_id: 'stream-abc',
            content: 'Hello',
            accumulated_content: 'Hello',
            chunk_index: 0,
          },
          timestamp: '2026-01-30T10:00:01Z',
        });
      });

      expect(result.current.content).toBe('Hello');
      expect(result.current.tokens).toEqual(['Hello']);
      expect(result.current.tokenCount).toBe(1);
      expect(onToken).toHaveBeenCalled();

      // Receive more tokens
      act(() => {
        onMessage({
          type: 'token',
          data: {
            stream_id: 'stream-abc',
            content: ' world',
            accumulated_content: 'Hello world',
            chunk_index: 1,
          },
          timestamp: '2026-01-30T10:00:02Z',
        });
      });

      expect(result.current.content).toBe('Hello world');
      expect(result.current.tokens).toEqual(['Hello', ' world']);
      expect(result.current.tokenCount).toBe(2);
    });
  });

  describe('stream_end event', () => {
    it('completes streaming and records final data', () => {
      const onStreamEnd = jest.fn();
      const { result } = renderHook(() =>
        useAiStreamingWebSocket({
          executionId: 'exec-123',
          onStreamEnd,
        })
      );

      const onMessage = mockSubscribe.mock.calls[0][0].onMessage;

      // Start stream
      act(() => {
        onMessage({
          type: 'stream_start',
          data: { stream_id: 'stream-abc' },
          timestamp: '2026-01-30T10:00:00Z',
        });
      });

      // End stream
      act(() => {
        onMessage({
          type: 'stream_end',
          data: {
            stream_id: 'stream-abc',
            content: 'Complete response',
            usage: { prompt_tokens: 50, completion_tokens: 100, total_tokens: 150 },
            cost: 0.015,
            duration_ms: 2500,
          },
          timestamp: '2026-01-30T10:00:03Z',
        });
      });

      expect(result.current.isStreaming).toBe(false);
      expect(result.current.content).toBe('Complete response');
      expect(result.current.usage).toEqual({
        prompt_tokens: 50,
        completion_tokens: 100,
        total_tokens: 150,
      });
      expect(result.current.cost).toBe(0.015);
      expect(result.current.elapsedMs).toBe(2500);
      expect(onStreamEnd).toHaveBeenCalled();
    });
  });

  describe('stream_error event', () => {
    it('handles errors and stops streaming', () => {
      const onStreamError = jest.fn();
      const { result } = renderHook(() =>
        useAiStreamingWebSocket({
          executionId: 'exec-123',
          onStreamError,
        })
      );

      const onMessage = mockSubscribe.mock.calls[0][0].onMessage;

      // Start stream
      act(() => {
        onMessage({
          type: 'stream_start',
          data: { stream_id: 'stream-abc' },
          timestamp: '2026-01-30T10:00:00Z',
        });
      });

      // Send some content
      act(() => {
        onMessage({
          type: 'token',
          data: {
            stream_id: 'stream-abc',
            content: 'Partial',
            accumulated_content: 'Partial',
            chunk_index: 0,
          },
          timestamp: '2026-01-30T10:00:01Z',
        });
      });

      // Error occurs
      act(() => {
        onMessage({
          type: 'stream_error',
          data: {
            stream_id: 'stream-abc',
            error: 'Connection lost',
            partial_content: 'Partial content',
          },
          timestamp: '2026-01-30T10:00:02Z',
        });
      });

      expect(result.current.isStreaming).toBe(false);
      expect(result.current.error).toBe('Connection lost');
      expect(result.current.content).toBe('Partial content');
      expect(onStreamError).toHaveBeenCalled();
    });
  });

  describe('reset', () => {
    it('resets state to initial values', () => {
      const { result } = renderHook(() =>
        useAiStreamingWebSocket({ executionId: 'exec-123' })
      );

      const onMessage = mockSubscribe.mock.calls[0][0].onMessage;

      // Start streaming
      act(() => {
        onMessage({
          type: 'stream_start',
          data: { stream_id: 'stream-abc' },
          timestamp: '2026-01-30T10:00:00Z',
        });
      });

      // Add content
      act(() => {
        onMessage({
          type: 'token',
          data: {
            stream_id: 'stream-abc',
            content: 'Test',
            accumulated_content: 'Test',
            chunk_index: 0,
          },
          timestamp: '2026-01-30T10:00:01Z',
        });
      });

      // Reset
      act(() => {
        result.current.reset();
      });

      expect(result.current.isStreaming).toBe(false);
      expect(result.current.streamId).toBeNull();
      expect(result.current.content).toBe('');
      expect(result.current.tokens).toEqual([]);
      expect(result.current.tokenCount).toBe(0);
    });
  });

  describe('cleanup', () => {
    it('unsubscribes on unmount', () => {
      const { unmount } = renderHook(() =>
        useAiStreamingWebSocket({ executionId: 'exec-123' })
      );

      unmount();

      expect(mockUnsubscribe).toHaveBeenCalled();
    });
  });
});

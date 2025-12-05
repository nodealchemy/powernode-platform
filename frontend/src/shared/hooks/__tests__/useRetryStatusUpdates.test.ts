import { renderHook, act } from '@testing-library/react';
import { useRetryStatusUpdates, useNodeRetryStatus, useCheckpointMonitor, useCircuitBreakerMonitor } from '../useRetryStatusUpdates';
import { useWebSocket } from '../useWebSocket';

// Mock the WebSocket hook
jest.mock('../useWebSocket');

// Get the mocked function using jest.mocked for better type safety
const mockUseWebSocket = jest.mocked(useWebSocket);

// Helper to capture subscription callbacks
const createMockWebSocket = () => {
  const subscriptions = new Map<string, (message: any) => void>();

  return {
    isConnected: true,
    error: null,
    lastConnected: new Date(),
    subscribe: jest.fn((subscription: any) => {
      const channel = subscription.channel;
      if (channel && subscription.onMessage) {
        subscriptions.set(channel, subscription.onMessage);
      }
      return jest.fn(); // unsubscribe function
    }),
    sendMessage: jest.fn(),
    // Helper to trigger messages
    trigger: (channel: string, message: any) => {
      const callback = subscriptions.get(channel);
      if (callback) callback(message);
    }
  };
};

describe('useRetryStatusUpdates', () => {
  const workflowRunId = 'test-workflow-run';
  let mockWS: ReturnType<typeof createMockWebSocket>;

  beforeEach(() => {
    mockWS = createMockWebSocket();
    mockUseWebSocket.mockReturnValue(mockWS as any);
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  describe('WebSocket subscription', () => {
    it('subscribes to workflow-specific channel', () => {
      renderHook(() => useRetryStatusUpdates({ workflowRunId }));

      expect(mockWS.subscribe).toHaveBeenCalledWith(
        expect.objectContaining({
          channel: `ai_workflow_run_${workflowRunId}`
        })
      );
    });

    it('subscribes to monitoring channel', () => {
      renderHook(() => useRetryStatusUpdates({ workflowRunId }));

      expect(mockWS.subscribe).toHaveBeenCalledWith(
        expect.objectContaining({
          channel: 'ai_monitoring_channel'
        })
      );
    });

    it('does not subscribe when enabled is false', () => {
      renderHook(() => useRetryStatusUpdates({ workflowRunId, enabled: false }));

      expect(mockWS.subscribe).not.toHaveBeenCalled();
    });

    it('does not subscribe when no workflowRunId provided', () => {
      renderHook(() => useRetryStatusUpdates({}));

      expect(mockWS.subscribe).not.toHaveBeenCalledWith(
        expect.objectContaining({
          channel: expect.stringContaining('ai_workflow_run')
        })
      );
    });
  });

  describe('retry event handling', () => {
    it('processes retry scheduled events', () => {
      const { result } = renderHook(() => useRetryStatusUpdates({ workflowRunId }));

      act(() => {
        mockWS.trigger(`ai_workflow_run_${workflowRunId}`, {
          type: 'node_retry_scheduled',
          node_id: 'node-1',
          node_execution_id: 'exec-1',
          retry_attempt: 1,
          max_retries: 3,
          delay_ms: 1000,
          scheduled_at: '2025-01-04T10:00:00Z'
        });
      });

      expect(result.current.retryUpdates).toHaveLength(1);
      expect(result.current.retryUpdates[0].type).toBe('node_retry_scheduled');
    });

    it('processes retry started events', () => {
      const { result } = renderHook(() => useRetryStatusUpdates({ workflowRunId }));

      act(() => {
        mockWS.trigger(`ai_workflow_run_${workflowRunId}`, {
          type: 'node_retry_started',
          node_id: 'node-2',
          node_execution_id: 'exec-2',
          retry_attempt: 2,
          max_retries: 5,
          delay_ms: 2000,
          scheduled_at: '2025-01-04T10:00:00Z'
        });
      });

      expect(result.current.retryUpdates).toHaveLength(1);
      expect(result.current.latestUpdate?.type).toBe('node_retry_started');
    });

    it('calls onRetryUpdate callback', () => {
      const onRetryUpdate = jest.fn();
      renderHook(() => useRetryStatusUpdates({ workflowRunId, onRetryUpdate }));

      const message = {
        type: 'node_retry_completed',
        node_id: 'node-3',
        node_execution_id: 'exec-3',
        retry_attempt: 1,
        max_retries: 3,
        delay_ms: 1000,
        scheduled_at: '2025-01-04T10:00:00Z'
      };

      act(() => {
        mockWS.trigger(`ai_workflow_run_${workflowRunId}`, message);
      });

      expect(onRetryUpdate).toHaveBeenCalledWith(expect.objectContaining({
        type: 'node_retry_completed',
        node_id: 'node-3'
      }));
    });

    it('adds timestamp if not provided', () => {
      const { result } = renderHook(() => useRetryStatusUpdates({ workflowRunId }));

      act(() => {
        mockWS.trigger(`ai_workflow_run_${workflowRunId}`, {
          type: 'node_retry_failed',
          node_id: 'node-4',
          node_execution_id: 'exec-4',
          retry_attempt: 3,
          max_retries: 3,
          delay_ms: 4000,
          scheduled_at: '2025-01-04T10:00:00Z'
          // No timestamp provided
        });
      });

      expect(result.current.retryUpdates[0].timestamp).toBeDefined();
    });
  });

  describe('checkpoint event handling', () => {
    it('processes checkpoint created events', () => {
      const { result } = renderHook(() => useRetryStatusUpdates({ workflowRunId }));

      act(() => {
        mockWS.trigger(`ai_workflow_run_${workflowRunId}`, {
          type: 'checkpoint_created',
          checkpoint_id: 'cp-1',
          checkpoint_type: 'node_completed',
          node_id: 'node-5',
          sequence_number: 1,
          progress_percentage: 50.0
        });
      });

      expect(result.current.checkpointEvents).toHaveLength(1);
      expect(result.current.checkpointEvents[0].type).toBe('checkpoint_created');
    });

    it('processes checkpoint restored events', () => {
      const { result } = renderHook(() => useRetryStatusUpdates({ workflowRunId }));

      act(() => {
        mockWS.trigger(`ai_workflow_run_${workflowRunId}`, {
          type: 'checkpoint_restored',
          checkpoint_id: 'cp-2',
          checkpoint_type: 'manual',
          sequence_number: 3,
          progress_percentage: 75.0
        });
      });

      expect(result.current.checkpointEvents).toHaveLength(1);
    });

    it('calls onCheckpointEvent callback', () => {
      const onCheckpointEvent = jest.fn();
      renderHook(() => useRetryStatusUpdates({ workflowRunId, onCheckpointEvent }));

      const message = {
        type: 'checkpoint_created',
        checkpoint_id: 'cp-3',
        checkpoint_type: 'batch_completed',
        sequence_number: 2,
        progress_percentage: 60.0
      };

      act(() => {
        mockWS.trigger(`ai_workflow_run_${workflowRunId}`, message);
      });

      expect(onCheckpointEvent).toHaveBeenCalledWith(expect.objectContaining({
        type: 'checkpoint_created',
        checkpoint_id: 'cp-3'
      }));
    });
  });

  describe('circuit breaker event handling', () => {
    it('processes circuit breaker state change events', () => {
      const { result } = renderHook(() => useRetryStatusUpdates({ workflowRunId }));

      act(() => {
        mockWS.trigger('ai_monitoring_channel', {
          type: 'circuit_breaker_state_change',
          service: 'ai_provider',
          old_state: 'closed',
          new_state: 'open'
        });
      });

      expect(result.current.circuitBreakerEvents).toHaveLength(1);
      expect(result.current.circuitBreakerEvents[0].type).toBe('circuit_breaker_state_change');
    });

    it('processes circuit breaker alert events', () => {
      const { result } = renderHook(() => useRetryStatusUpdates({ workflowRunId }));

      act(() => {
        mockWS.trigger('ai_monitoring_channel', {
          type: 'circuit_breaker_alert',
          service: 'webhook_service',
          severity: 'high',
          message: 'Circuit breaker opened'
        });
      });

      expect(result.current.circuitBreakerEvents).toHaveLength(1);
    });

    it('calls onCircuitBreakerEvent callback', () => {
      const onCircuitBreakerEvent = jest.fn();
      renderHook(() => useRetryStatusUpdates({ workflowRunId, onCircuitBreakerEvent }));

      const message = {
        type: 'circuit_breaker_warning',
        service: 'external_api',
        severity: 'medium',
        message: 'High failure rate detected'
      };

      act(() => {
        mockWS.trigger('ai_monitoring_channel', message);
      });

      expect(onCircuitBreakerEvent).toHaveBeenCalledWith(expect.objectContaining({
        type: 'circuit_breaker_warning',
        service: 'external_api'
      }));
    });

    it('handles services array in circuit breaker events', () => {
      const { result } = renderHook(() => useRetryStatusUpdates({ workflowRunId }));

      act(() => {
        mockWS.trigger('ai_monitoring_channel', {
          type: 'circuit_breaker_state_change',
          services: ['service1', 'service2'],
          new_state: 'open'
        });
      });

      expect(result.current.circuitBreakerEvents[0].service).toBe('service1');
    });
  });

  describe('helper methods', () => {
    it('getNodeRetryStatus returns latest status for node', () => {
      const { result } = renderHook(() => useRetryStatusUpdates({ workflowRunId }));

      act(() => {
        mockWS.trigger(`ai_workflow_run_${workflowRunId}`, {
          type: 'node_retry_started',
          node_id: 'target-node',
          node_execution_id: 'exec-1',
          retry_attempt: 1,
          max_retries: 3,
          delay_ms: 1000,
          scheduled_at: '2025-01-04T10:00:00Z',
          timestamp: '2025-01-04T10:00:00Z'
        });

        mockWS.trigger(`ai_workflow_run_${workflowRunId}`, {
          type: 'node_retry_completed',
          node_id: 'target-node',
          node_execution_id: 'exec-1',
          retry_attempt: 1,
          max_retries: 3,
          delay_ms: 1000,
          scheduled_at: '2025-01-04T10:00:00Z',
          timestamp: '2025-01-04T10:01:00Z'
        });
      });

      const status = result.current.getNodeRetryStatus('target-node');
      expect(status?.type).toBe('node_retry_completed');
    });

    it('getLatestCheckpoint returns most recent checkpoint event', () => {
      const { result } = renderHook(() => useRetryStatusUpdates({ workflowRunId }));

      act(() => {
        mockWS.trigger(`ai_workflow_run_${workflowRunId}`, {
          type: 'checkpoint_created',
          checkpoint_id: 'cp-1',
          checkpoint_type: 'node_completed',
          sequence_number: 1,
          progress_percentage: 25.0,
          timestamp: '2025-01-04T10:00:00Z'
        });

        mockWS.trigger(`ai_workflow_run_${workflowRunId}`, {
          type: 'checkpoint_created',
          checkpoint_id: 'cp-2',
          checkpoint_type: 'manual',
          sequence_number: 2,
          progress_percentage: 50.0,
          timestamp: '2025-01-04T10:05:00Z'
        });
      });

      const latest = result.current.getLatestCheckpoint();
      expect(latest?.checkpoint_id).toBe('cp-2');
    });

    it('getServiceCircuitStatus returns latest status for service', () => {
      const { result } = renderHook(() => useRetryStatusUpdates({ workflowRunId }));

      act(() => {
        mockWS.trigger('ai_monitoring_channel', {
          type: 'circuit_breaker_state_change',
          service: 'test_service',
          old_state: 'closed',
          new_state: 'open',
          timestamp: '2025-01-04T10:00:00Z'
        });
      });

      const status = result.current.getServiceCircuitStatus('test_service');
      expect(status?.new_state).toBe('open');
    });
  });

  describe('clear methods', () => {
    it('clearRetryUpdates clears all retry updates', () => {
      const { result } = renderHook(() => useRetryStatusUpdates({ workflowRunId }));

      act(() => {
        mockWS.trigger(`ai_workflow_run_${workflowRunId}`, {
          type: 'node_retry_started',
          node_id: 'node-1',
          node_execution_id: 'exec-1',
          retry_attempt: 1,
          max_retries: 3,
          delay_ms: 1000,
          scheduled_at: '2025-01-04T10:00:00Z'
        });
      });

      expect(result.current.retryUpdates).toHaveLength(1);

      act(() => {
        result.current.clearRetryUpdates();
      });

      expect(result.current.retryUpdates).toHaveLength(0);
      expect(result.current.latestUpdate).toBeNull();
    });

    it('clearCheckpointEvents clears all checkpoint events', () => {
      const { result } = renderHook(() => useRetryStatusUpdates({ workflowRunId }));

      act(() => {
        mockWS.trigger(`ai_workflow_run_${workflowRunId}`, {
          type: 'checkpoint_created',
          checkpoint_id: 'cp-1',
          checkpoint_type: 'manual',
          sequence_number: 1,
          progress_percentage: 50.0
        });
      });

      expect(result.current.checkpointEvents).toHaveLength(1);

      act(() => {
        result.current.clearCheckpointEvents();
      });

      expect(result.current.checkpointEvents).toHaveLength(0);
    });

    it('clearCircuitBreakerEvents clears all circuit breaker events', () => {
      const { result } = renderHook(() => useRetryStatusUpdates({ workflowRunId }));

      act(() => {
        mockWS.trigger('ai_monitoring_channel', {
          type: 'circuit_breaker_state_change',
          service: 'test_service',
          new_state: 'open'
        });
      });

      expect(result.current.circuitBreakerEvents).toHaveLength(1);

      act(() => {
        result.current.clearCircuitBreakerEvents();
      });

      expect(result.current.circuitBreakerEvents).toHaveLength(0);
    });
  });

  describe('retry statistics', () => {
    it('calculates total retries', () => {
      const { result } = renderHook(() => useRetryStatusUpdates({ workflowRunId }));

      act(() => {
        ['node-1', 'node-2', 'node-3'].forEach((nodeId, index) => {
          mockWS.trigger(`ai_workflow_run_${workflowRunId}`, {
            type: 'node_retry_started',
            node_id: nodeId,
            node_execution_id: `exec-${index}`,
            retry_attempt: 1,
            max_retries: 3,
            delay_ms: 1000,
            scheduled_at: '2025-01-04T10:00:00Z'
          });
        });
      });

      expect(result.current.retryStats.total_retries).toBe(3);
    });

    it('tracks successful retries', () => {
      const { result } = renderHook(() => useRetryStatusUpdates({ workflowRunId }));

      act(() => {
        mockWS.trigger(`ai_workflow_run_${workflowRunId}`, {
          type: 'node_retry_completed',
          node_id: 'node-1',
          node_execution_id: 'exec-1',
          retry_attempt: 1,
          max_retries: 3,
          delay_ms: 1000,
          scheduled_at: '2025-01-04T10:00:00Z'
        });

        mockWS.trigger(`ai_workflow_run_${workflowRunId}`, {
          type: 'node_retry_completed',
          node_id: 'node-2',
          node_execution_id: 'exec-2',
          retry_attempt: 1,
          max_retries: 3,
          delay_ms: 1000,
          scheduled_at: '2025-01-04T10:00:00Z'
        });
      });

      expect(result.current.retryStats.successful_retries).toBe(2);
    });

    it('tracks failed retries', () => {
      const { result } = renderHook(() => useRetryStatusUpdates({ workflowRunId }));

      act(() => {
        mockWS.trigger(`ai_workflow_run_${workflowRunId}`, {
          type: 'node_retry_failed',
          node_id: 'node-1',
          node_execution_id: 'exec-1',
          retry_attempt: 3,
          max_retries: 3,
          delay_ms: 4000,
          scheduled_at: '2025-01-04T10:00:00Z'
        });
      });

      expect(result.current.retryStats.failed_retries).toBe(1);
    });

    it('tracks exhausted retries', () => {
      const { result } = renderHook(() => useRetryStatusUpdates({ workflowRunId }));

      act(() => {
        mockWS.trigger(`ai_workflow_run_${workflowRunId}`, {
          type: 'retries_exhausted',
          node_id: 'node-1',
          node_execution_id: 'exec-1',
          retry_attempt: 3,
          max_retries: 3,
          delay_ms: 8000,
          scheduled_at: '2025-01-04T10:00:00Z'
        });
      });

      expect(result.current.retryStats.exhausted_retries).toBe(1);
    });

    it('tracks active retries', () => {
      const { result } = renderHook(() => useRetryStatusUpdates({ workflowRunId }));

      act(() => {
        mockWS.trigger(`ai_workflow_run_${workflowRunId}`, {
          type: 'node_retry_scheduled',
          node_id: 'node-1',
          node_execution_id: 'exec-1',
          retry_attempt: 1,
          max_retries: 3,
          delay_ms: 1000,
          scheduled_at: '2025-01-04T10:00:00Z'
        });

        mockWS.trigger(`ai_workflow_run_${workflowRunId}`, {
          type: 'node_retry_started',
          node_id: 'node-2',
          node_execution_id: 'exec-2',
          retry_attempt: 1,
          max_retries: 3,
          delay_ms: 1000,
          scheduled_at: '2025-01-04T10:00:00Z'
        });
      });

      expect(result.current.retryStats.active_retries).toBe(2);
    });
  });

  describe('connection status', () => {
    it('reports connected when WebSocket is connected', () => {
      const { result } = renderHook(() => useRetryStatusUpdates({ workflowRunId }));

      expect(result.current.isConnected).toBe(true);
    });

    it('reports disconnected when WebSocket is disconnected', () => {
      mockWS.isConnected = false;
      const { result } = renderHook(() => useRetryStatusUpdates({ workflowRunId }));

      expect(result.current.isConnected).toBe(false);
    });
  });
});

describe('useNodeRetryStatus', () => {
  let mockWS: ReturnType<typeof createMockWebSocket>;

  beforeEach(() => {
    mockWS = createMockWebSocket();
    mockUseWebSocket.mockReturnValue(mockWS as any);
  });

  it('returns status for specific node', () => {
    const { result } = renderHook(() => useNodeRetryStatus('workflow-1', 'target-node'));

    act(() => {
      mockWS.trigger('ai_workflow_run_workflow-1', {
        type: 'node_retry_started',
        node_id: 'target-node',
        node_execution_id: 'exec-1',
        retry_attempt: 1,
        max_retries: 3,
        delay_ms: 1000,
        scheduled_at: '2025-01-04T10:00:00Z'
      });
    });

    expect(result.current?.node_id).toBe('target-node');
    expect(result.current?.type).toBe('node_retry_started');
  });

  it('ignores updates for other nodes', () => {
    const { result } = renderHook(() => useNodeRetryStatus('workflow-1', 'target-node'));

    act(() => {
      mockWS.trigger('ai_workflow_run_workflow-1', {
        type: 'node_retry_started',
        node_id: 'other-node',
        node_execution_id: 'exec-1',
        retry_attempt: 1,
        max_retries: 3,
        delay_ms: 1000,
        scheduled_at: '2025-01-04T10:00:00Z'
      });
    });

    expect(result.current).toBeNull();
  });
});

describe('useCheckpointMonitor', () => {
  let mockWS: ReturnType<typeof createMockWebSocket>;

  beforeEach(() => {
    mockWS = createMockWebSocket();
    mockUseWebSocket.mockReturnValue(mockWS as any);
  });

  it('tracks checkpoint events', () => {
    const { result } = renderHook(() => useCheckpointMonitor('workflow-1'));

    act(() => {
      mockWS.trigger('ai_workflow_run_workflow-1', {
        type: 'checkpoint_created',
        checkpoint_id: 'cp-1',
        checkpoint_type: 'node_completed',
        sequence_number: 1,
        progress_percentage: 33.3
      });
    });

    expect(result.current.checkpoints).toHaveLength(1);
    expect(result.current.latestCheckpoint?.checkpoint_id).toBe('cp-1');
    expect(result.current.checkpointCount).toBe(1);
  });
});

describe('useCircuitBreakerMonitor', () => {
  let mockWS: ReturnType<typeof createMockWebSocket>;

  beforeEach(() => {
    mockWS = createMockWebSocket();
    mockUseWebSocket.mockReturnValue(mockWS as any);
  });

  it('tracks service states', () => {
    const { result } = renderHook(() => useCircuitBreakerMonitor());

    act(() => {
      mockWS.trigger('ai_monitoring_channel', {
        type: 'circuit_breaker_state_change',
        service: 'test_service',
        old_state: 'closed',
        new_state: 'open'
      });
    });

    const state = result.current.getServiceState('test_service');
    expect(state?.new_state).toBe('open');
  });

  it('tracks alerts', () => {
    const { result } = renderHook(() => useCircuitBreakerMonitor());

    act(() => {
      mockWS.trigger('ai_monitoring_channel', {
        type: 'circuit_breaker_alert',
        service: 'test_service',
        severity: 'high',
        message: 'Circuit breaker opened'
      });
    });

    expect(result.current.alerts).toHaveLength(1);
  });

  it('counts unhealthy services', () => {
    const { result } = renderHook(() => useCircuitBreakerMonitor());

    act(() => {
      mockWS.trigger('ai_monitoring_channel', {
        type: 'circuit_breaker_state_change',
        service: 'service1',
        new_state: 'open'
      });

      mockWS.trigger('ai_monitoring_channel', {
        type: 'circuit_breaker_state_change',
        service: 'service2',
        new_state: 'open'
      });
    });

    expect(result.current.unhealthyServices).toBe(2);
  });

  it('counts degraded services', () => {
    const { result } = renderHook(() => useCircuitBreakerMonitor());

    act(() => {
      mockWS.trigger('ai_monitoring_channel', {
        type: 'circuit_breaker_state_change',
        service: 'service1',
        new_state: 'half_open'
      });
    });

    expect(result.current.degradedServices).toBe(1);
  });

  it('allows clearing alerts', () => {
    const { result } = renderHook(() => useCircuitBreakerMonitor());

    act(() => {
      mockWS.trigger('ai_monitoring_channel', {
        type: 'circuit_breaker_alert',
        service: 'test_service',
        severity: 'high',
        message: 'Alert'
      });
    });

    expect(result.current.alerts).toHaveLength(1);

    act(() => {
      result.current.clearAlerts();
    });

    expect(result.current.alerts).toHaveLength(0);
  });
});

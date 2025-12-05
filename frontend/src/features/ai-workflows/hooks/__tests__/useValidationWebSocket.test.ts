import { renderHook, waitFor, act } from '@testing-library/react';
import { useValidationWebSocket } from '../useValidationWebSocket';
import type { WorkflowValidationResult } from '@/shared/types/workflow';

// Mock useNotifications hook
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({
    addNotification: jest.fn(),
  }),
}));

describe('useValidationWebSocket', () => {
  const mockWorkflowId = 'workflow-123';

  let mockChannel: any;
  let mockCable: any;

  beforeEach(() => {
    mockChannel = {
      unsubscribe: jest.fn(),
    };

    mockCable = {
      subscriptions: {
        create: jest.fn(() => mockChannel),
      },
    };

    // Mock ActionCable on window
    (window as any).ActionCable = mockCable;
  });

  afterEach(() => {
    delete (window as any).ActionCable;
    jest.clearAllMocks();
  });

  it('establishes WebSocket connection on mount', () => {
    renderHook(() =>
      useValidationWebSocket({
        workflowId: mockWorkflowId,
        enabled: true,
      })
    );

    expect(mockCable.subscriptions.create).toHaveBeenCalledWith(
      {
        channel: 'AiOrchestrationChannel',
        workflow_id: mockWorkflowId,
      },
      expect.objectContaining({
        connected: expect.any(Function),
        disconnected: expect.any(Function),
        received: expect.any(Function),
        rejected: expect.any(Function),
      })
    );
  });

  it('does not connect when enabled is false', () => {
    renderHook(() =>
      useValidationWebSocket({
        workflowId: mockWorkflowId,
        enabled: false,
      })
    );

    expect(mockCable.subscriptions.create).not.toHaveBeenCalled();
  });

  it('unsubscribes on unmount', () => {
    const { unmount } = renderHook(() =>
      useValidationWebSocket({
        workflowId: mockWorkflowId,
        enabled: true,
      })
    );

    unmount();

    expect(mockChannel.unsubscribe).toHaveBeenCalled();
  });

  it('registers connected callback with correct signature', () => {
    renderHook(() =>
      useValidationWebSocket({
        workflowId: mockWorkflowId,
        enabled: true,
      })
    );

    // Verify the connected callback was registered
    const createCall = mockCable.subscriptions.create.mock.calls[0];
    const channelCallbacks = createCall[1];

    // Verify all callbacks are functions
    expect(typeof channelCallbacks.connected).toBe('function');
    expect(typeof channelCallbacks.disconnected).toBe('function');
    expect(typeof channelCallbacks.received).toBe('function');
    expect(typeof channelCallbacks.rejected).toBe('function');
  });

  it('handles validation_result messages', async () => {
    const onValidationUpdate = jest.fn();

    const { result } = renderHook(() =>
      useValidationWebSocket({
        workflowId: mockWorkflowId,
        enabled: true,
        onValidationUpdate,
      })
    );

    const mockValidation: WorkflowValidationResult = {
      workflow_id: mockWorkflowId,
      workflow_name: 'Test Workflow',
      overall_status: 'valid',
      health_score: 95,
      total_nodes: 5,
      validated_nodes: 5,
      issues: [],
      validation_timestamp: new Date().toISOString(),
      validation_duration_ms: 234,
      categories: {
        configuration: 0,
        connection: 0,
        data_flow: 0,
        performance: 0,
        security: 0,
      },
    };

    // Simulate receiving validation result
    const createCall = mockCable.subscriptions.create.mock.calls[0];
    const channelCallbacks = createCall[1];
    channelCallbacks.received({
      type: 'validation_result',
      validation: mockValidation,
    });

    await waitFor(() => {
      expect(result.current.validationResult).toEqual(mockValidation);
      expect(onValidationUpdate).toHaveBeenCalledWith(mockValidation);
    });
  });

  it('handles validation_started messages', async () => {
    const { result } = renderHook(() =>
      useValidationWebSocket({
        workflowId: mockWorkflowId,
        enabled: true,
      })
    );

    expect(result.current.isValidating).toBe(false);

    // Simulate validation started
    const createCall = mockCable.subscriptions.create.mock.calls[0];
    const channelCallbacks = createCall[1];
    channelCallbacks.received({
      type: 'validation_started',
    });

    await waitFor(() => {
      expect(result.current.isValidating).toBe(true);
    });
  });

  it('handles validation_progress messages', async () => {
    const { result } = renderHook(() =>
      useValidationWebSocket({
        workflowId: mockWorkflowId,
        enabled: true,
      })
    );

    expect(result.current.validationProgress).toBe(0);

    // Simulate progress update
    const createCall = mockCable.subscriptions.create.mock.calls[0];
    const channelCallbacks = createCall[1];
    channelCallbacks.received({
      type: 'validation_progress',
      progress: {
        current_step: 'Validating node configuration',
        total_steps: 10,
        completed_steps: 5,
        percentage: 50,
      },
    });

    await waitFor(() => {
      expect(result.current.validationProgress).toBe(50);
    });
  });

  it('handles validation_health_alerts messages', async () => {
    const onHealthAlert = jest.fn();

    const { result } = renderHook(() =>
      useValidationWebSocket({
        workflowId: mockWorkflowId,
        enabled: true,
        onHealthAlert,
      })
    );

    const mockAlert = {
      workflow_id: mockWorkflowId,
      workflow_name: 'Test Workflow',
      type: 'health_degradation' as const,
      severity: 'error' as const,
      message: 'Health score dropped by 15 points',
      metadata: { previous_score: 90, current_score: 75 },
      created_at: new Date().toISOString(),
    };

    // Simulate alert
    const createCall = mockCable.subscriptions.create.mock.calls[0];
    const channelCallbacks = createCall[1];
    channelCallbacks.received({
      type: 'validation_health_alerts',
      alerts: [mockAlert],
    });

    await waitFor(() => {
      expect(result.current.healthAlerts).toHaveLength(1);
      expect(onHealthAlert).toHaveBeenCalledWith(mockAlert);
    });
  });

  it('clears health alerts when clearAlerts is called', async () => {
    const { result } = renderHook(() =>
      useValidationWebSocket({
        workflowId: mockWorkflowId,
        enabled: true,
      })
    );

    // Add an alert
    const createCall = mockCable.subscriptions.create.mock.calls[0];
    const channelCallbacks = createCall[1];
    channelCallbacks.received({
      type: 'validation_health_alerts',
      alerts: [
        {
          workflow_id: mockWorkflowId,
          workflow_name: 'Test',
          type: 'stale_validation' as const,
          severity: 'warning' as const,
          message: 'Test alert',
          metadata: {},
          created_at: new Date().toISOString(),
        },
      ],
    });

    await waitFor(() => {
      expect(result.current.healthAlerts).toHaveLength(1);
    });

    // Clear alerts - wrap in act() to properly flush state updates
    await act(async () => {
      result.current.clearAlerts();
    });

    expect(result.current.healthAlerts).toHaveLength(0);
  });
});

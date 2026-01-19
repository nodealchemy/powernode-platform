import { render, screen, waitFor } from '@testing-library/react';
import { LiveRetryStatus } from '../LiveRetryStatus';
import { useRetryStatusUpdates } from '@/shared/hooks/useRetryStatusUpdates';

// Mock the WebSocket hook
jest.mock('@/shared/hooks/useRetryStatusUpdates');

const mockUseRetryStatusUpdates = useRetryStatusUpdates as jest.MockedFunction<typeof useRetryStatusUpdates>;

describe('LiveRetryStatus', () => {
  const defaultMockReturn = {
    isConnected: true,
    retryUpdates: [],
    latestUpdate: null,
    retryStats: {
      total_retries: 0,
      successful_retries: 0,
      failed_retries: 0,
      exhausted_retries: 0,
      active_retries: 0
    },
    getNodeRetryStatus: jest.fn(),
    clearRetryUpdates: jest.fn(),
    checkpointEvents: [],
    getLatestCheckpoint: jest.fn(),
    clearCheckpointEvents: jest.fn(),
    circuitBreakerEvents: [],
    getServiceCircuitStatus: jest.fn(),
    clearCircuitBreakerEvents: jest.fn()
  };

  beforeEach(() => {
    mockUseRetryStatusUpdates.mockReturnValue(defaultMockReturn);
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  describe('rendering', () => {
    it('renders retry status component', () => {
      render(<LiveRetryStatus workflowRunId="test-run-id" />);

      expect(screen.getByText('Live Retry Status')).toBeInTheDocument();
    });

    it('shows connection status indicator', () => {
      render(<LiveRetryStatus workflowRunId="test-run-id" />);

      expect(screen.getByText('Connected')).toBeInTheDocument();
    });

    it('shows disconnected state when not connected', () => {
      mockUseRetryStatusUpdates.mockReturnValue({
        ...defaultMockReturn,
        isConnected: false
      });

      render(<LiveRetryStatus workflowRunId="test-run-id" />);

      expect(screen.getByText('Disconnected')).toBeInTheDocument();
    });

    it('displays retry statistics', () => {
      mockUseRetryStatusUpdates.mockReturnValue({
        ...defaultMockReturn,
        retryStats: {
          total_retries: 10,
          successful_retries: 7,
          failed_retries: 2,
          exhausted_retries: 1,
          active_retries: 3
        }
      });

      render(<LiveRetryStatus workflowRunId="test-run-id" />);

      expect(screen.getByText('10')).toBeInTheDocument(); // Total
      expect(screen.getByText('7')).toBeInTheDocument(); // Success
      expect(screen.getByText('2')).toBeInTheDocument(); // Failed
      expect(screen.getByText('3')).toBeInTheDocument(); // Active
    });
  });

  describe('retry updates display', () => {
    it('displays recent retry activity', () => {
      const updates = [
        {
          type: 'node_retry_started' as const,
          node_id: 'node-1',
          node_execution_id: 'exec-1',
          retry_attempt: 1,
          max_retries: 3,
          delay_ms: 1000,
          scheduled_at: '2025-01-04T10:00:00Z',
          timestamp: '2025-01-04T10:00:00Z'
        }
      ];

      mockUseRetryStatusUpdates.mockReturnValue({
        ...defaultMockReturn,
        retryUpdates: updates
      });

      render(<LiveRetryStatus workflowRunId="test-run-id" />);

      expect(screen.getByText(/Retrying/i)).toBeInTheDocument();
      expect(screen.getByText(/node-1/i)).toBeInTheDocument();
    });

    it('shows retry attempt information', () => {
      const updates = [
        {
          type: 'node_retry_scheduled' as const,
          node_id: 'node-2',
          node_execution_id: 'exec-2',
          retry_attempt: 2,
          max_retries: 5,
          delay_ms: 2000,
          scheduled_at: '2025-01-04T10:00:00Z',
          timestamp: '2025-01-04T10:00:00Z'
        }
      ];

      mockUseRetryStatusUpdates.mockReturnValue({
        ...defaultMockReturn,
        retryUpdates: updates
      });

      render(<LiveRetryStatus workflowRunId="test-run-id" />);

      expect(screen.getByText(/Attempt.*2.*5/i)).toBeInTheDocument();
    });

    it('shows delay information', () => {
      const updates = [
        {
          type: 'node_retry_scheduled' as const,
          node_id: 'node-3',
          node_execution_id: 'exec-3',
          retry_attempt: 1,
          max_retries: 3,
          delay_ms: 5000,
          scheduled_at: '2025-01-04T10:00:00Z',
          timestamp: '2025-01-04T10:00:00Z'
        }
      ];

      mockUseRetryStatusUpdates.mockReturnValue({
        ...defaultMockReturn,
        retryUpdates: updates
      });

      render(<LiveRetryStatus workflowRunId="test-run-id" />);

      // formatDelay outputs 5.0s for 5000ms - displayed as "Delay: 5.0s"
      expect(screen.getByText(/Delay:.*5\.0s/)).toBeInTheDocument();
    });

    it('displays error type when available', () => {
      const updates = [
        {
          type: 'node_retry_failed' as const,
          node_id: 'node-4',
          node_execution_id: 'exec-4',
          retry_attempt: 1,
          max_retries: 3,
          delay_ms: 1000,
          scheduled_at: '2025-01-04T10:00:00Z',
          error_type: 'timeout',
          timestamp: '2025-01-04T10:00:00Z'
        }
      ];

      mockUseRetryStatusUpdates.mockReturnValue({
        ...defaultMockReturn,
        retryUpdates: updates
      });

      render(<LiveRetryStatus workflowRunId="test-run-id" />);

      expect(screen.getByText('timeout')).toBeInTheDocument();
    });

    it('shows empty state when no updates', () => {
      render(<LiveRetryStatus workflowRunId="test-run-id" />);

      expect(screen.getByText(/No retry activity yet/i)).toBeInTheDocument();
    });

    it('limits display to 10 most recent updates', () => {
      const updates = Array.from({ length: 15 }, (_, i) => ({
        type: 'node_retry_started' as const,
        node_id: `node-${i}`,
        node_execution_id: `exec-${i}`,
        retry_attempt: 1,
        max_retries: 3,
        delay_ms: 1000,
        scheduled_at: '2025-01-04T10:00:00Z',
        timestamp: `2025-01-04T10:${String(i).padStart(2, '0')}:00Z`
      }));

      mockUseRetryStatusUpdates.mockReturnValue({
        ...defaultMockReturn,
        retryUpdates: updates
      });

      render(<LiveRetryStatus workflowRunId="test-run-id" />);

      const activityItems = screen.getAllByText(/node-/i);
      expect(activityItems.length).toBeLessThanOrEqual(10);
    });
  });

  describe('status icons and labels', () => {
    it('shows correct label for retry scheduled', () => {
      const updates = [
        {
          type: 'node_retry_scheduled' as const,
          node_id: 'node-1',
          node_execution_id: 'exec-1',
          retry_attempt: 1,
          max_retries: 3,
          delay_ms: 1000,
          scheduled_at: '2025-01-04T10:00:00Z',
          timestamp: '2025-01-04T10:00:00Z'
        }
      ];

      mockUseRetryStatusUpdates.mockReturnValue({
        ...defaultMockReturn,
        retryUpdates: updates
      });

      render(<LiveRetryStatus workflowRunId="test-run-id" />);

      // Check for scheduled status label
      expect(screen.getByText('Retry Scheduled')).toBeInTheDocument();
    });

    it('shows correct label for retry started', () => {
      const updates = [
        {
          type: 'node_retry_started' as const,
          node_id: 'node-1',
          node_execution_id: 'exec-1',
          retry_attempt: 1,
          max_retries: 3,
          delay_ms: 1000,
          scheduled_at: '2025-01-04T10:00:00Z',
          timestamp: '2025-01-04T10:00:00Z'
        }
      ];

      mockUseRetryStatusUpdates.mockReturnValue({
        ...defaultMockReturn,
        retryUpdates: updates
      });

      render(<LiveRetryStatus workflowRunId="test-run-id" />);

      // Check for retrying status label
      expect(screen.getByText('Retrying...')).toBeInTheDocument();
    });

    it('shows correct label for retry completed', () => {
      const updates = [
        {
          type: 'node_retry_completed' as const,
          node_id: 'node-1',
          node_execution_id: 'exec-1',
          retry_attempt: 1,
          max_retries: 3,
          delay_ms: 1000,
          scheduled_at: '2025-01-04T10:00:00Z',
          timestamp: '2025-01-04T10:00:00Z'
        }
      ];

      mockUseRetryStatusUpdates.mockReturnValue({
        ...defaultMockReturn,
        retryUpdates: updates
      });

      render(<LiveRetryStatus workflowRunId="test-run-id" />);

      // Check for success status label
      expect(screen.getByText('Retry Successful')).toBeInTheDocument();
    });

    it('shows correct label for retry failed', () => {
      const updates = [
        {
          type: 'node_retry_failed' as const,
          node_id: 'node-1',
          node_execution_id: 'exec-1',
          retry_attempt: 1,
          max_retries: 3,
          delay_ms: 1000,
          scheduled_at: '2025-01-04T10:00:00Z',
          timestamp: '2025-01-04T10:00:00Z'
        }
      ];

      mockUseRetryStatusUpdates.mockReturnValue({
        ...defaultMockReturn,
        retryUpdates: updates
      });

      render(<LiveRetryStatus workflowRunId="test-run-id" />);

      // Check for failed status label
      expect(screen.getByText('Retry Failed')).toBeInTheDocument();
    });
  });

  describe('exhausted retries warning', () => {
    it('shows warning when retries are exhausted', () => {
      mockUseRetryStatusUpdates.mockReturnValue({
        ...defaultMockReturn,
        retryStats: {
          ...defaultMockReturn.retryStats,
          exhausted_retries: 2
        }
      });

      render(<LiveRetryStatus workflowRunId="test-run-id" />);

      expect(screen.getByText(/2 nodes have exhausted all retry attempts/i)).toBeInTheDocument();
    });

    it('uses singular form for single exhausted node', () => {
      mockUseRetryStatusUpdates.mockReturnValue({
        ...defaultMockReturn,
        retryStats: {
          ...defaultMockReturn.retryStats,
          exhausted_retries: 1
        }
      });

      render(<LiveRetryStatus workflowRunId="test-run-id" />);

      expect(screen.getByText(/1 node has exhausted all retry attempts/i)).toBeInTheDocument();
    });

    it('hides warning when no exhausted retries', () => {
      render(<LiveRetryStatus workflowRunId="test-run-id" />);

      expect(screen.queryByText(/exhausted/i)).not.toBeInTheDocument();
    });
  });

  describe('node-specific status', () => {
    it('filters updates for specific node when nodeId provided', () => {
      const updates = [
        {
          type: 'node_retry_started' as const,
          node_id: 'target-node',
          node_execution_id: 'exec-1',
          retry_attempt: 1,
          max_retries: 3,
          delay_ms: 1000,
          scheduled_at: '2025-01-04T10:00:00Z',
          timestamp: '2025-01-04T10:00:00Z'
        },
        {
          type: 'node_retry_started' as const,
          node_id: 'other-node',
          node_execution_id: 'exec-2',
          retry_attempt: 1,
          max_retries: 3,
          delay_ms: 1000,
          scheduled_at: '2025-01-04T10:00:00Z',
          timestamp: '2025-01-04T10:00:00Z'
        }
      ];

      mockUseRetryStatusUpdates.mockReturnValue({
        ...defaultMockReturn,
        retryUpdates: updates
      });

      render(<LiveRetryStatus workflowRunId="test-run-id" nodeId="target-node" />);

      expect(screen.getByText(/target-node/i)).toBeInTheDocument();
      expect(screen.queryByText(/other-node/i)).not.toBeInTheDocument();
    });
  });

  describe('compact mode', () => {
    it('renders compact view when compact prop is true', () => {
      const updates = [
        {
          type: 'node_retry_started' as const,
          node_id: 'node-1',
          node_execution_id: 'exec-1',
          retry_attempt: 1,
          max_retries: 3,
          delay_ms: 1000,
          scheduled_at: '2025-01-04T10:00:00Z',
          retry_stats: {
            current_attempt: 1,
            retries_remaining: 2,
            total_retry_time_ms: 1000,
            last_retry_at: '2025-01-04T10:00:00Z',
            next_retry_delay_ms: 2000,
            retryable: true
          },
          timestamp: '2025-01-04T10:00:00Z'
        }
      ];

      mockUseRetryStatusUpdates.mockReturnValue({
        ...defaultMockReturn,
        retryUpdates: updates,
        latestUpdate: updates[0]
      });

      render(<LiveRetryStatus workflowRunId="test-run-id" compact />);

      expect(screen.queryByText('Live Retry Status')).not.toBeInTheDocument();
      expect(screen.getByText(/Retrying/i)).toBeInTheDocument();
    });

    it('shows attempt count in compact mode', () => {
      const updates = [
        {
          type: 'node_retry_started' as const,
          node_id: 'node-1',
          node_execution_id: 'exec-1',
          retry_attempt: 2,
          max_retries: 5,
          delay_ms: 1000,
          scheduled_at: '2025-01-04T10:00:00Z',
          retry_stats: {
            current_attempt: 2,
            retries_remaining: 3,
            total_retry_time_ms: 3000,
            last_retry_at: '2025-01-04T10:00:00Z',
            next_retry_delay_ms: 4000,
            retryable: true
          },
          timestamp: '2025-01-04T10:00:00Z'
        }
      ];

      mockUseRetryStatusUpdates.mockReturnValue({
        ...defaultMockReturn,
        retryUpdates: updates,
        latestUpdate: updates[0]
      });

      render(<LiveRetryStatus workflowRunId="test-run-id" compact />);

      expect(screen.getByText(/Attempt 2\/5/i)).toBeInTheDocument();
    });
  });

  describe('time formatting', () => {
    it('formats delays in milliseconds', () => {
      const updates = [
        {
          type: 'node_retry_scheduled' as const,
          node_id: 'node-1',
          node_execution_id: 'exec-1',
          retry_attempt: 1,
          max_retries: 3,
          delay_ms: 500,
          scheduled_at: '2025-01-04T10:00:00Z',
          timestamp: '2025-01-04T10:00:00Z'
        }
      ];

      mockUseRetryStatusUpdates.mockReturnValue({
        ...defaultMockReturn,
        retryUpdates: updates
      });

      render(<LiveRetryStatus workflowRunId="test-run-id" />);

      // formatDelay outputs 500ms - displayed as "Delay: 500ms"
      expect(screen.getByText(/Delay:.*500ms/)).toBeInTheDocument();
    });

    it('formats delays in seconds', () => {
      const updates = [
        {
          type: 'node_retry_scheduled' as const,
          node_id: 'node-1',
          node_execution_id: 'exec-1',
          retry_attempt: 1,
          max_retries: 3,
          delay_ms: 3500,
          scheduled_at: '2025-01-04T10:00:00Z',
          timestamp: '2025-01-04T10:00:00Z'
        }
      ];

      mockUseRetryStatusUpdates.mockReturnValue({
        ...defaultMockReturn,
        retryUpdates: updates
      });

      render(<LiveRetryStatus workflowRunId="test-run-id" />);

      // formatDelay outputs 3.5s - displayed as "Delay: 3.5s"
      expect(screen.getByText(/Delay:.*3\.5s/)).toBeInTheDocument();
    });

    it('formats delays in minutes', () => {
      const updates = [
        {
          type: 'node_retry_scheduled' as const,
          node_id: 'node-1',
          node_execution_id: 'exec-1',
          retry_attempt: 1,
          max_retries: 3,
          delay_ms: 90000,
          scheduled_at: '2025-01-04T10:00:00Z',
          timestamp: '2025-01-04T10:00:00Z'
        }
      ];

      mockUseRetryStatusUpdates.mockReturnValue({
        ...defaultMockReturn,
        retryUpdates: updates
      });

      render(<LiveRetryStatus workflowRunId="test-run-id" />);

      // formatDelay outputs 1.5m - displayed as "Delay: 1.5m"
      expect(screen.getByText(/Delay:.*1\.5m/)).toBeInTheDocument();
    });
  });

  describe('real-time updates', () => {
    it('updates when new retry events are received', async () => {
      const { rerender } = render(<LiveRetryStatus workflowRunId="test-run-id" />);

      const newUpdates = [
        {
          type: 'node_retry_started' as const,
          node_id: 'new-node',
          node_execution_id: 'exec-new',
          retry_attempt: 1,
          max_retries: 3,
          delay_ms: 1000,
          scheduled_at: '2025-01-04T10:00:00Z',
          timestamp: '2025-01-04T10:00:00Z'
        }
      ];

      mockUseRetryStatusUpdates.mockReturnValue({
        ...defaultMockReturn,
        retryUpdates: newUpdates
      });

      rerender(<LiveRetryStatus workflowRunId="test-run-id" />);

      await waitFor(() => {
        expect(screen.getByText(/new-node/i)).toBeInTheDocument();
      });
    });

    it('updates statistics when retries complete', async () => {
      const { rerender } = render(<LiveRetryStatus workflowRunId="test-run-id" />);

      mockUseRetryStatusUpdates.mockReturnValue({
        ...defaultMockReturn,
        retryStats: {
          total_retries: 5,
          successful_retries: 3,
          failed_retries: 2,
          exhausted_retries: 0,
          active_retries: 0
        }
      });

      rerender(<LiveRetryStatus workflowRunId="test-run-id" />);

      await waitFor(() => {
        expect(screen.getByText('5')).toBeInTheDocument();
        expect(screen.getByText('3')).toBeInTheDocument();
      });
    });
  });
});

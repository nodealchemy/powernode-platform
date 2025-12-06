import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { Provider } from 'react-redux';
import { configureStore } from '@reduxjs/toolkit';
import { McpToolExecutionHistory } from './McpToolExecutionHistory';
import { mcpApi } from '@/shared/services/ai/McpApiService';
import uiReducer from '@/shared/services/slices/uiSlice';

// Mock the MCP API
jest.mock('@/shared/services/ai/McpApiService', () => ({
  mcpApi: {
    getExecutionHistory: jest.fn(),
    cancelExecution: jest.fn(),
  },
}));

const mockMcpApi = mcpApi as jest.Mocked<typeof mcpApi>;

const mockExecutions = {
  executions: [
    {
      id: 'exec-1',
      status: 'completed' as const,
      user_id: 'user-1',
      user_name: 'John Doe',
      parameters: { input: 'test' },
      result: { output: 'result' },
      duration_ms: 150,
      created_at: new Date().toISOString(),
      started_at: new Date().toISOString(),
      completed_at: new Date().toISOString(),
    },
    {
      id: 'exec-2',
      status: 'failed' as const,
      user_id: 'user-1',
      user_name: 'John Doe',
      parameters: { input: 'bad' },
      error_message: 'Something went wrong',
      duration_ms: 50,
      created_at: new Date(Date.now() - 3600000).toISOString(),
      started_at: new Date(Date.now() - 3600000).toISOString(),
      completed_at: new Date(Date.now() - 3600000).toISOString(),
    },
    {
      id: 'exec-3',
      status: 'running' as const,
      user_id: 'user-1',
      user_name: 'John Doe',
      parameters: { input: 'pending' },
      created_at: new Date().toISOString(),
      started_at: new Date().toISOString(),
    },
  ],
  mcp_tool: { id: 'tool-1', name: 'test-tool' },
  mcp_server: { id: 'server-1', name: 'test-server' },
  pagination: {
    current_page: 1,
    per_page: 10,
    total_pages: 1,
    total_count: 3,
  },
  meta: {
    pending_count: 0,
    running_count: 1,
    success_count: 1,
    failed_count: 1,
    cancelled_count: 0,
  },
};

const createTestStore = () =>
  configureStore({
    reducer: {
      ui: uiReducer,
    },
  });

const renderComponent = (props = {}) => {
  const defaultProps = {
    serverId: 'server-1',
    toolId: 'tool-1',
    toolName: 'test-tool',
    ...props,
  };

  const store = createTestStore();

  return render(
    <Provider store={store}>
      <McpToolExecutionHistory {...defaultProps} />
    </Provider>
  );
};

describe('McpToolExecutionHistory', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockMcpApi.getExecutionHistory.mockResolvedValue(mockExecutions);
  });

  it('renders loading state initially', () => {
    mockMcpApi.getExecutionHistory.mockReturnValue(new Promise(() => {})); // Never resolves
    renderComponent();
    expect(screen.getByText('Loading execution history...')).toBeInTheDocument();
  });

  it('renders execution history after loading', async () => {
    renderComponent();

    await waitFor(() => {
      expect(screen.getByText('Execution History')).toBeInTheDocument();
    });

    // Check stats are displayed
    expect(screen.getByText('1 passed')).toBeInTheDocument();
    expect(screen.getByText('1 failed')).toBeInTheDocument();
    expect(screen.getByText('1 running')).toBeInTheDocument();
  });

  it('displays empty state when no executions', async () => {
    mockMcpApi.getExecutionHistory.mockResolvedValue({
      ...mockExecutions,
      executions: [],
    });

    renderComponent();

    await waitFor(() => {
      expect(screen.getByText('No execution history for test-tool')).toBeInTheDocument();
    });
  });

  it('expands execution to show details', async () => {
    renderComponent();

    await waitFor(() => {
      expect(screen.getByText('Completed')).toBeInTheDocument();
    });

    // Click to expand first execution
    const completedBadge = screen.getByText('Completed');
    fireEvent.click(completedBadge.closest('[class*="cursor-pointer"]')!);

    // Check that parameters and result are shown
    await waitFor(() => {
      expect(screen.getByText('Parameters:')).toBeInTheDocument();
      expect(screen.getByText('Result:')).toBeInTheDocument();
    });
  });

  it('shows error message for failed executions', async () => {
    renderComponent();

    await waitFor(() => {
      expect(screen.getByText('Failed')).toBeInTheDocument();
    });

    // Click to expand failed execution
    const failedBadge = screen.getByText('Failed');
    fireEvent.click(failedBadge.closest('[class*="cursor-pointer"]')!);

    await waitFor(() => {
      expect(screen.getByText('Error:')).toBeInTheDocument();
      expect(screen.getByText('Something went wrong')).toBeInTheDocument();
    });
  });

  it('refreshes history when refresh button is clicked', async () => {
    renderComponent();

    await waitFor(() => {
      expect(screen.getByText('Execution History')).toBeInTheDocument();
    });

    // Get the call count before clicking refresh
    const callsBefore = mockMcpApi.getExecutionHistory.mock.calls.length;

    // Find and click refresh button
    const refreshButton = screen.getByTitle('Refresh history');
    fireEvent.click(refreshButton);

    // Verify at least one more call was made after clicking refresh
    await waitFor(() => {
      expect(mockMcpApi.getExecutionHistory.mock.calls.length).toBeGreaterThan(callsBefore);
    });
  });

  it('refreshes when refreshTrigger prop changes', async () => {
    const store = createTestStore();

    const { rerender } = render(
      <Provider store={store}>
        <McpToolExecutionHistory
          serverId="server-1"
          toolId="tool-1"
          toolName="test-tool"
          refreshTrigger={0}
        />
      </Provider>
    );

    // Wait for initial load to complete
    await waitFor(() => {
      expect(screen.getByText('Execution History')).toBeInTheDocument();
    });

    // Get call count before rerender (may be 1 or 2 due to StrictMode)
    const callsBeforeRerender = mockMcpApi.getExecutionHistory.mock.calls.length;
    expect(callsBeforeRerender).toBeGreaterThanOrEqual(1);

    rerender(
      <Provider store={store}>
        <McpToolExecutionHistory
          serverId="server-1"
          toolId="tool-1"
          toolName="test-tool"
          refreshTrigger={1}
        />
      </Provider>
    );

    // Verify at least one more call was made after rerender with new trigger
    await waitFor(() => {
      expect(mockMcpApi.getExecutionHistory.mock.calls.length).toBeGreaterThan(callsBeforeRerender);
    });
  });

  it('calls onExecutionSelect when view details is clicked', async () => {
    const onExecutionSelect = jest.fn();
    renderComponent({ onExecutionSelect });

    await waitFor(() => {
      expect(screen.getByText('Completed')).toBeInTheDocument();
    });

    // Expand first execution
    const completedBadge = screen.getByText('Completed');
    fireEvent.click(completedBadge.closest('[class*="cursor-pointer"]')!);

    await waitFor(() => {
      expect(screen.getByText('View Full Details')).toBeInTheDocument();
    });

    fireEvent.click(screen.getByText('View Full Details'));
    expect(onExecutionSelect).toHaveBeenCalledWith(mockExecutions.executions[0]);
  });

  it('handles API error gracefully', async () => {
    mockMcpApi.getExecutionHistory.mockRejectedValue(new Error('API Error'));
    renderComponent();

    // Should show empty state or error handling
    await waitFor(() => {
      // The component should handle the error gracefully
      expect(mockMcpApi.getExecutionHistory).toHaveBeenCalled();
    });
  });

  it('cancels execution when cancel button is clicked', async () => {
    mockMcpApi.cancelExecution.mockResolvedValue({
      execution: { ...mockExecutions.executions[2], status: 'cancelled' as const },
      message: 'Execution cancelled successfully',
    });

    renderComponent();

    await waitFor(() => {
      expect(screen.getByText('Running')).toBeInTheDocument();
    });

    // Find the cancel button within the running execution row
    const runningBadge = screen.getByText('Running');
    const runningCard = runningBadge.closest('[class*="overflow-hidden"]');
    const cancelButton = runningCard?.querySelector('button:not([title="Refresh history"])');

    expect(cancelButton).toBeTruthy();
    if (cancelButton) {
      fireEvent.click(cancelButton);

      await waitFor(() => {
        expect(mockMcpApi.cancelExecution).toHaveBeenCalledWith('server-1', 'tool-1', 'exec-3');
      });
    }
  });
});

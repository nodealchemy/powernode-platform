import { render, screen, fireEvent, act } from '@testing-library/react';
import { TaskEventStream } from '../components/TaskEventStream';
import { a2aTasksApiService } from '@/shared/services/ai';

// Mock scrollIntoView which isn't available in jsdom
Element.prototype.scrollIntoView = jest.fn();

// Mock the API service
jest.mock('@/shared/services/ai', () => ({
  a2aTasksApiService: {
    subscribeToTask: jest.fn(),
  },
}));

// Mock useNotifications hook
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({
    addNotification: jest.fn(),
  }),
}));

describe('TaskEventStream', () => {
  let mockClose: jest.Mock;
  let openCallback: (() => void) | undefined;
  let statusCallback: ((task: unknown) => void) | undefined;
  let progressCallback: ((progress: unknown) => void) | undefined;
  let errorCallback: ((error: unknown) => void) | undefined;

  beforeEach(() => {
    jest.clearAllMocks();
    mockClose = jest.fn();
    openCallback = undefined;
    statusCallback = undefined;
    progressCallback = undefined;
    errorCallback = undefined;

    // Mock subscribeToTask to capture callbacks and return subscription
    (a2aTasksApiService.subscribeToTask as jest.Mock).mockImplementation(
      (_taskId: string, callbacks: {
        onOpen?: () => void;
        onStatus?: (task: unknown) => void;
        onProgress?: (progress: unknown) => void;
        onError?: (error: unknown) => void;
      }) => {
        openCallback = callbacks.onOpen;
        statusCallback = callbacks.onStatus;
        progressCallback = callbacks.onProgress;
        errorCallback = callbacks.onError;

        return {
          eventSource: {} as EventSource,
          close: mockClose,
        };
      }
    );
  });

  /** Helper: render with autoConnect and simulate the onOpen callback firing */
  const renderConnected = async (props?: Partial<{ taskId: string }>) => {
    const result = render(<TaskEventStream taskId={props?.taskId ?? 'task-1'} autoConnect={true} />);
    // Simulate the SSE connection opening after subscribeToTask returns
    await act(async () => {
      openCallback?.();
    });
    return result;
  };

  it('renders event stream header', () => {
    render(<TaskEventStream taskId="task-1" autoConnect={false} />);

    expect(screen.getByText('Event Stream')).toBeInTheDocument();
  });

  it('shows disconnected state when autoConnect is false', () => {
    render(<TaskEventStream taskId="task-1" autoConnect={false} />);

    expect(screen.getByText('Disconnected')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /connect/i })).toBeInTheDocument();
  });

  it('connects and shows connected state when autoConnect is true', async () => {
    await renderConnected();

    expect(a2aTasksApiService.subscribeToTask).toHaveBeenCalledWith(
      'task-1',
      expect.objectContaining({
        onStatus: expect.any(Function),
        onProgress: expect.any(Function),
      })
    );
    expect(screen.getByText('Connected')).toBeInTheDocument();
  });

  it('shows stop button when connecting or connected', async () => {
    render(<TaskEventStream taskId="task-1" autoConnect={true} />);

    // Stop button should be visible immediately during connecting state
    expect(screen.getByRole('button', { name: /stop/i })).toBeInTheDocument();

    // Also visible after fully connected
    await act(async () => {
      openCallback?.();
    });
    expect(screen.getByRole('button', { name: /stop/i })).toBeInTheDocument();
  });

  it('disconnects when stop button clicked', async () => {
    await renderConnected();

    const stopButton = screen.getByRole('button', { name: /stop/i });
    fireEvent.click(stopButton);

    expect(mockClose).toHaveBeenCalled();
  });

  it('shows status events when received', async () => {
    await renderConnected();

    // Trigger a status update through the captured callback
    await act(async () => {
      statusCallback?.({ status: { state: 'active' } });
    });

    expect(screen.getByText(/task\.status/)).toBeInTheDocument();
  });

  it('shows progress bar when progress event received', async () => {
    await renderConnected();

    await act(async () => {
      progressCallback?.({ current: 50, total: 100, message: 'Processing...' });
    });

    expect(screen.getByText(/50 \/ 100/)).toBeInTheDocument();
    // "Processing..." appears in both progress bar and event log
    expect(screen.getAllByText(/Processing\.\.\./).length).toBeGreaterThanOrEqual(1);
  });

  it('displays current task status', async () => {
    await renderConnected();

    await act(async () => {
      statusCallback?.({ status: { state: 'completed' } });
    });

    expect(screen.getByText('completed')).toBeInTheDocument();
  });

  it('handles error events', async () => {
    await renderConnected();

    await act(async () => {
      errorCallback?.('Connection failed');
    });

    expect(screen.getByText(/task\.error/)).toBeInTheDocument();
  });

  it('clears events when clear button clicked', async () => {
    await renderConnected();

    // Add an event
    await act(async () => {
      statusCallback?.({ status: { state: 'active' } });
    });

    expect(screen.getByText(/task\.status/)).toBeInTheDocument();

    // Clear events
    const clearButton = screen.getByRole('button', { name: /clear/i });
    fireEvent.click(clearButton);

    expect(screen.queryByText(/task\.status/)).not.toBeInTheDocument();
  });

  it('can reconnect after disconnecting', async () => {
    render(<TaskEventStream taskId="task-1" autoConnect={true} />);

    // Wait for connection
    await act(async () => {
      openCallback?.();
    });

    // Disconnect
    const stopButton = screen.getByRole('button', { name: /stop/i });
    fireEvent.click(stopButton);

    // Should show Connect button after disconnect
    const connectButton = screen.getByRole('button', { name: /connect/i });
    fireEvent.click(connectButton);

    expect(a2aTasksApiService.subscribeToTask).toHaveBeenCalledTimes(2);
  });
});

import { render, screen, waitFor, fireEvent } from '@testing-library/react';
import { TaskEventStream } from '../components/TaskEventStream';
import { a2aTasksApiService } from '@/shared/services/ai';

// Mock the API service
jest.mock('@/shared/services/ai', () => ({
  a2aTasksApiService: {
    pollTaskEvents: jest.fn(),
  },
}));

// Mock useNotifications hook
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({
    addNotification: jest.fn(),
  }),
}));

describe('TaskEventStream', () => {
  const mockEvents = [
    {
      id: '1',
      event_type: 'status_change',
      data: { from_status: 'pending', to_status: 'active' },
      created_at: '2025-01-15T10:00:01Z',
    },
    {
      id: '2',
      event_type: 'progress',
      data: { current: 50, total: 100, message: 'Processing...' },
      created_at: '2025-01-15T10:00:02Z',
    },
    {
      id: '3',
      event_type: 'artifact_added',
      data: { artifact_id: 'art-1', name: 'result.json' },
      created_at: '2025-01-15T10:00:03Z',
    },
    {
      id: '4',
      event_type: 'status_change',
      data: { from_status: 'active', to_status: 'completed' },
      created_at: '2025-01-15T10:00:04Z',
    },
  ];

  beforeEach(() => {
    jest.clearAllMocks();
    (a2aTasksApiService.pollTaskEvents as jest.Mock).mockResolvedValue({
      events: mockEvents,
    });
  });

  it('renders loading state initially', () => {
    (a2aTasksApiService.pollTaskEvents as jest.Mock).mockImplementation(
      () => new Promise(() => {})
    );

    render(<TaskEventStream taskId="task-1" />);

    expect(screen.getByText(/loading events/i)).toBeInTheDocument();
  });

  it('renders events after loading', async () => {
    render(<TaskEventStream taskId="task-1" />);

    await waitFor(() => {
      expect(screen.getByText(/status_change/i)).toBeInTheDocument();
      expect(screen.getByText(/progress/i)).toBeInTheDocument();
      expect(screen.getByText(/artifact_added/i)).toBeInTheDocument();
    });
  });

  it('shows event details', async () => {
    render(<TaskEventStream taskId="task-1" />);

    await waitFor(() => {
      expect(screen.getByText(/pending.*active/i)).toBeInTheDocument();
      expect(screen.getByText(/Processing/i)).toBeInTheDocument();
      expect(screen.getByText(/result.json/i)).toBeInTheDocument();
    });
  });

  it('shows progress bar for progress events', async () => {
    render(<TaskEventStream taskId="task-1" />);

    await waitFor(() => {
      expect(screen.getByText(/50%|50 \/ 100/)).toBeInTheDocument();
    });
  });

  it('polls for new events', async () => {
    jest.useFakeTimers();

    render(<TaskEventStream taskId="task-1" autoRefresh={true} />);

    await waitFor(() => {
      expect(a2aTasksApiService.pollTaskEvents).toHaveBeenCalledTimes(1);
    });

    jest.advanceTimersByTime(5000);

    await waitFor(() => {
      expect(a2aTasksApiService.pollTaskEvents).toHaveBeenCalledTimes(2);
    });

    jest.useRealTimers();
  });

  it('stops polling when task is terminal', async () => {
    jest.useFakeTimers();

    render(<TaskEventStream taskId="task-1" taskStatus="completed" autoRefresh={true} />);

    await waitFor(() => {
      expect(a2aTasksApiService.pollTaskEvents).toHaveBeenCalledTimes(1);
    });

    // Advance time - should not poll again since task is completed
    jest.advanceTimersByTime(5000);

    expect(a2aTasksApiService.pollTaskEvents).toHaveBeenCalledTimes(1);

    jest.useRealTimers();
  });

  it('displays empty state when no events', async () => {
    (a2aTasksApiService.pollTaskEvents as jest.Mock).mockResolvedValue({
      events: [],
    });

    render(<TaskEventStream taskId="task-1" />);

    await waitFor(() => {
      expect(screen.getByText(/no events/i)).toBeInTheDocument();
    });
  });

  it('shows timestamps for events', async () => {
    render(<TaskEventStream taskId="task-1" />);

    await waitFor(() => {
      // Should show time stamps
      expect(screen.getByText(/10:00/)).toBeInTheDocument();
    });
  });

  it('allows manual refresh', async () => {
    render(<TaskEventStream taskId="task-1" autoRefresh={false} />);

    await waitFor(() => {
      expect(a2aTasksApiService.pollTaskEvents).toHaveBeenCalledTimes(1);
    });

    const refreshButton = screen.getByRole('button', { name: /refresh/i });
    fireEvent.click(refreshButton);

    await waitFor(() => {
      expect(a2aTasksApiService.pollTaskEvents).toHaveBeenCalledTimes(2);
    });
  });

  it('shows error events with error styling', async () => {
    (a2aTasksApiService.pollTaskEvents as jest.Mock).mockResolvedValue({
      events: [
        {
          id: '5',
          event_type: 'error',
          data: { message: 'Something went wrong' },
          created_at: '2025-01-15T10:00:05Z',
        },
      ],
    });

    render(<TaskEventStream taskId="task-1" />);

    await waitFor(() => {
      expect(screen.getByText(/something went wrong/i)).toBeInTheDocument();
    });
  });
});

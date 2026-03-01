import { render, screen, waitFor, fireEvent } from '@testing-library/react';
import { TaskDetail } from '../components/TaskDetail';
import { a2aTasksApiService } from '@/shared/services/ai';

// Mock the API service
jest.mock('@/shared/services/ai', () => ({
  a2aTasksApiService: {
    getTaskDetails: jest.fn(),
    cancelTask: jest.fn(),
    getArtifacts: jest.fn(),
    provideInput: jest.fn(),
  },
}));

// Mock useNotifications hook
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({
    addNotification: jest.fn(),
  }),
}));

describe('TaskDetail', () => {
  const mockTask = {
    id: 'task-uuid-1234-5678',
    sessionId: 'session-1',
    status: { state: 'completed' },
    message: {
      role: 'user',
      parts: [{ type: 'text', text: 'Process this' }],
    },
    artifacts: [],
    history: [],
    metadata: {
      priority: 'high',
      submitted_at: '2025-01-15T10:00:00Z',
      started_at: '2025-01-15T10:00:01Z',
      completed_at: '2025-01-15T10:00:05Z',
    },
  };

  const mockArtifacts = [
    {
      id: 'artifact-1',
      name: 'result.json',
      mimeType: 'application/json',
      description: 'Processing result',
    },
  ];

  const mockOnClose = jest.fn();

  beforeEach(() => {
    jest.clearAllMocks();
    (a2aTasksApiService.getTaskDetails as jest.Mock).mockResolvedValue({
      task: mockTask,
    });
    (a2aTasksApiService.getArtifacts as jest.Mock).mockResolvedValue({
      artifacts: mockArtifacts,
    });
  });

  it('renders loading state initially', () => {
    (a2aTasksApiService.getTaskDetails as jest.Mock).mockImplementation(
      () => new Promise(() => {})
    );

    render(<TaskDetail taskId="task-uuid-1234-5678" onClose={mockOnClose} />);

    expect(screen.getByText(/loading/i)).toBeInTheDocument();
  });

  it('renders task details after loading', async () => {
    render(<TaskDetail taskId="task-uuid-1234-5678" onClose={mockOnClose} />);

    await waitFor(() => {
      // "Completed" may appear multiple times (badge and timeline)
      expect(screen.getAllByText('Completed').length).toBeGreaterThanOrEqual(1);
    });

    // Verify task ID is shown somewhere (appears in title and ID line)
    await waitFor(() => {
      expect(screen.getAllByText(/task-uuid-1234/).length).toBeGreaterThanOrEqual(1);
    });
  });

  it('displays message section', async () => {
    render(<TaskDetail taskId="task-uuid-1234-5678" onClose={mockOnClose} />);

    await waitFor(() => {
      expect(screen.getByText('Message')).toBeInTheDocument();
    });
  });

  it('displays message text content', async () => {
    render(<TaskDetail taskId="task-uuid-1234-5678" onClose={mockOnClose} />);

    await waitFor(() => {
      expect(screen.getByText('Process this')).toBeInTheDocument();
    });
  });

  it('displays artifacts section', async () => {
    render(<TaskDetail taskId="task-uuid-1234-5678" onClose={mockOnClose} />);

    await waitFor(() => {
      expect(screen.getByText('result.json')).toBeInTheDocument();
    });
  });

  it('shows timeline section', async () => {
    render(<TaskDetail taskId="task-uuid-1234-5678" onClose={mockOnClose} />);

    await waitFor(() => {
      expect(screen.getByText('Timeline')).toBeInTheDocument();
    });
  });

  it('shows duration in timeline', async () => {
    render(<TaskDetail taskId="task-uuid-1234-5678" onClose={mockOnClose} />);

    await waitFor(() => {
      expect(screen.getByText('Duration')).toBeInTheDocument();
    });
  });

  it('shows cancel button for active tasks', async () => {
    (a2aTasksApiService.getTaskDetails as jest.Mock).mockResolvedValue({
      task: { ...mockTask, status: { state: 'working' }, metadata: { ...mockTask.metadata, completed_at: undefined } },
    });

    render(<TaskDetail taskId="task-uuid-1234-5678" onClose={mockOnClose} />);

    await waitFor(() => {
      expect(screen.getByRole('button', { name: /cancel/i })).toBeInTheDocument();
    });
  });

  it('calls cancel API when cancel button clicked', async () => {
    (a2aTasksApiService.getTaskDetails as jest.Mock).mockResolvedValue({
      task: { ...mockTask, status: { state: 'working' }, metadata: { ...mockTask.metadata, completed_at: undefined } },
    });
    (a2aTasksApiService.cancelTask as jest.Mock).mockResolvedValue({
      success: true,
    });

    render(<TaskDetail taskId="task-uuid-1234-5678" onClose={mockOnClose} />);

    await waitFor(() => {
      expect(screen.getByRole('button', { name: /cancel/i })).toBeInTheDocument();
    });

    fireEvent.click(screen.getByRole('button', { name: /cancel/i }));

    await waitFor(() => {
      expect(a2aTasksApiService.cancelTask).toHaveBeenCalledWith(
        'task-uuid-1234-5678',
        'Cancelled by user'
      );
    });
  });

  it('shows error message for failed tasks', async () => {
    (a2aTasksApiService.getTaskDetails as jest.Mock).mockResolvedValue({
      task: { ...mockTask, status: { state: 'failed' }, error: { code: 'timeout', message: 'Connection timeout' } },
    });

    render(<TaskDetail taskId="task-uuid-1234-5678" onClose={mockOnClose} />);

    await waitFor(() => {
      expect(screen.getByText(/connection timeout/i)).toBeInTheDocument();
    });
  });

  it('shows input required section when status is input_required', async () => {
    (a2aTasksApiService.getTaskDetails as jest.Mock).mockResolvedValue({
      task: { ...mockTask, status: { state: 'input-required' }, metadata: { ...mockTask.metadata, completed_at: undefined } },
    });

    render(<TaskDetail taskId="task-uuid-1234-5678" onClose={mockOnClose} />);

    await waitFor(() => {
      // "Input Required" may appear multiple times (header and badge)
      expect(screen.getAllByText('Input Required').length).toBeGreaterThanOrEqual(1);
    });
  });

  it('handles refresh button click', async () => {
    render(<TaskDetail taskId="task-uuid-1234-5678" onClose={mockOnClose} />);

    await waitFor(() => {
      expect(screen.getAllByText('Completed').length).toBeGreaterThanOrEqual(1);
    });

    const refreshButton = screen.getByRole('button', { name: /refresh/i });
    fireEvent.click(refreshButton);

    await waitFor(() => {
      expect(a2aTasksApiService.getTaskDetails).toHaveBeenCalledTimes(2);
    });
  });

  it('shows go back button on error', async () => {
    (a2aTasksApiService.getTaskDetails as jest.Mock).mockRejectedValue(
      new Error('Failed to load')
    );

    render(<TaskDetail taskId="task-uuid-1234-5678" onClose={mockOnClose} />);

    await waitFor(() => {
      expect(screen.getByRole('button', { name: /go back/i })).toBeInTheDocument();
    });

    fireEvent.click(screen.getByRole('button', { name: /go back/i }));

    expect(mockOnClose).toHaveBeenCalled();
  });
});

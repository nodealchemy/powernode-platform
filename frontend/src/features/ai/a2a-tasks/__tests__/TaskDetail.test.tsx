import { render, screen, waitFor, fireEvent } from '@testing-library/react';
import { TaskDetail } from '../components/TaskDetail';
import { a2aTasksApiService } from '@/shared/services/ai';

// Mock the API service
jest.mock('@/shared/services/ai', () => ({
  a2aTasksApiService: {
    getTask: jest.fn(),
    getTaskDetails: jest.fn(),
    cancelTask: jest.fn(),
    getTaskArtifacts: jest.fn(),
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
    id: 'task-uuid-1',
    task_id: 'task-uuid-1',
    status: 'completed',
    from_agent: { id: 'agent-1', name: 'Agent A' },
    to_agent: { id: 'agent-2', name: 'Agent B' },
    input: { message: { role: 'user', parts: [{ type: 'text', text: 'Process this' }] } },
    output: { result: 'Processed successfully' },
    artifacts: [
      {
        artifact_id: 'artifact-1',
        name: 'result.json',
        mime_type: 'application/json',
        description: 'Processing result',
      },
    ],
    metadata: { priority: 'high' },
    created_at: '2025-01-15T10:00:00Z',
    started_at: '2025-01-15T10:00:01Z',
    completed_at: '2025-01-15T10:00:05Z',
  };

  const mockOnBack = jest.fn();

  beforeEach(() => {
    jest.clearAllMocks();
    (a2aTasksApiService.getTask as jest.Mock).mockResolvedValue({
      task: mockTask,
    });
    (a2aTasksApiService.getTaskDetails as jest.Mock).mockResolvedValue({
      task: mockTask,
    });
    (a2aTasksApiService.getTaskArtifacts as jest.Mock).mockResolvedValue({
      artifacts: mockTask.artifacts,
    });
  });

  it('renders loading state initially', () => {
    (a2aTasksApiService.getTask as jest.Mock).mockImplementation(
      () => new Promise(() => {})
    );

    render(<TaskDetail taskId="task-uuid-1" onBack={mockOnBack} />);

    expect(screen.getByText(/loading/i)).toBeInTheDocument();
  });

  it('renders task details after loading', async () => {
    render(<TaskDetail taskId="task-uuid-1" onBack={mockOnBack} />);

    await waitFor(() => {
      expect(screen.getByText('task-uuid-1')).toBeInTheDocument();
      expect(screen.getByText('completed')).toBeInTheDocument();
    });
  });

  it('displays from and to agents', async () => {
    render(<TaskDetail taskId="task-uuid-1" onBack={mockOnBack} />);

    await waitFor(() => {
      expect(screen.getByText('Agent A')).toBeInTheDocument();
      expect(screen.getByText('Agent B')).toBeInTheDocument();
    });
  });

  it('displays input message', async () => {
    render(<TaskDetail taskId="task-uuid-1" onBack={mockOnBack} />);

    await waitFor(() => {
      expect(screen.getByText(/process this/i)).toBeInTheDocument();
    });
  });

  it('displays output result', async () => {
    render(<TaskDetail taskId="task-uuid-1" onBack={mockOnBack} />);

    await waitFor(() => {
      expect(screen.getByText(/processed successfully/i)).toBeInTheDocument();
    });
  });

  it('displays artifacts section', async () => {
    render(<TaskDetail taskId="task-uuid-1" onBack={mockOnBack} />);

    await waitFor(() => {
      expect(screen.getByText('result.json')).toBeInTheDocument();
    });
  });

  it('displays metadata', async () => {
    render(<TaskDetail taskId="task-uuid-1" onBack={mockOnBack} />);

    await waitFor(() => {
      expect(screen.getByText(/high/i)).toBeInTheDocument();
    });
  });

  it('shows timeline section', async () => {
    render(<TaskDetail taskId="task-uuid-1" onBack={mockOnBack} />);

    await waitFor(() => {
      expect(screen.getByText(/timeline/i)).toBeInTheDocument();
    });
  });

  it('calculates and shows duration', async () => {
    render(<TaskDetail taskId="task-uuid-1" onBack={mockOnBack} />);

    await waitFor(() => {
      expect(screen.getByText(/4s|4000ms|duration/i)).toBeInTheDocument();
    });
  });

  it('calls onBack when back button clicked', async () => {
    render(<TaskDetail taskId="task-uuid-1" onBack={mockOnBack} />);

    await waitFor(() => {
      expect(screen.getByText('task-uuid-1')).toBeInTheDocument();
    });

    fireEvent.click(screen.getByRole('button', { name: /back/i }));

    expect(mockOnBack).toHaveBeenCalled();
  });

  it('shows cancel button for active tasks', async () => {
    (a2aTasksApiService.getTask as jest.Mock).mockResolvedValue({
      task: { ...mockTask, status: 'active', completed_at: null },
    });

    render(<TaskDetail taskId="task-uuid-1" onBack={mockOnBack} />);

    await waitFor(() => {
      expect(screen.getByRole('button', { name: /cancel/i })).toBeInTheDocument();
    });
  });

  it('calls cancel API when cancel button clicked', async () => {
    (a2aTasksApiService.getTask as jest.Mock).mockResolvedValue({
      task: { ...mockTask, status: 'active', completed_at: null },
    });
    (a2aTasksApiService.cancelTask as jest.Mock).mockResolvedValue({
      success: true,
    });

    render(<TaskDetail taskId="task-uuid-1" onBack={mockOnBack} />);

    await waitFor(() => {
      expect(screen.getByRole('button', { name: /cancel/i })).toBeInTheDocument();
    });

    fireEvent.click(screen.getByRole('button', { name: /cancel/i }));

    await waitFor(() => {
      expect(a2aTasksApiService.cancelTask).toHaveBeenCalledWith('task-uuid-1', expect.any(Object));
    });
  });

  it('shows error message for failed tasks', async () => {
    (a2aTasksApiService.getTask as jest.Mock).mockResolvedValue({
      task: { ...mockTask, status: 'failed', error_message: 'Connection timeout' },
    });

    render(<TaskDetail taskId="task-uuid-1" onBack={mockOnBack} />);

    await waitFor(() => {
      expect(screen.getByText(/connection timeout/i)).toBeInTheDocument();
    });
  });
});

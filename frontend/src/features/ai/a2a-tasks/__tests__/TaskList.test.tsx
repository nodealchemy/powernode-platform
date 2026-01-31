import { render, screen, waitFor, fireEvent } from '@testing-library/react';
import { TaskList } from '../components/TaskList';
import { a2aTasksApiService } from '@/shared/services/ai';

// Mock the API service
jest.mock('@/shared/services/ai', () => ({
  a2aTasksApiService: {
    getTasks: jest.fn(),
  },
}));

// Mock useNotifications hook
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({
    addNotification: jest.fn(),
  }),
}));

describe('TaskList', () => {
  const mockTasks = [
    {
      id: '1',
      task_id: 'task-uuid-1',
      status: 'completed',
      from_agent: { id: 'agent-1', name: 'Agent A' },
      to_agent: { id: 'agent-2', name: 'Agent B' },
      created_at: '2025-01-15T10:00:00Z',
      started_at: '2025-01-15T10:00:01Z',
      completed_at: '2025-01-15T10:00:05Z',
    },
    {
      id: '2',
      task_id: 'task-uuid-2',
      status: 'active',
      from_agent: { id: 'agent-1', name: 'Agent A' },
      to_agent: { id: 'agent-3', name: 'Agent C' },
      created_at: '2025-01-15T11:00:00Z',
      started_at: '2025-01-15T11:00:01Z',
    },
    {
      id: '3',
      task_id: 'task-uuid-3',
      status: 'failed',
      from_agent: { id: 'agent-2', name: 'Agent B' },
      to_agent: { id: 'agent-1', name: 'Agent A' },
      error_message: 'Task timed out',
      created_at: '2025-01-15T09:00:00Z',
    },
  ];

  const mockOnSelect = jest.fn();

  beforeEach(() => {
    jest.clearAllMocks();
    (a2aTasksApiService.getTasks as jest.Mock).mockResolvedValue({
      items: mockTasks,
      pagination: { current_page: 1, total_count: 3, total_pages: 1 },
    });
  });

  it('renders loading state initially', () => {
    (a2aTasksApiService.getTasks as jest.Mock).mockImplementation(
      () => new Promise(() => {})
    );

    render(<TaskList onSelect={mockOnSelect} />);

    expect(screen.getByText(/loading/i)).toBeInTheDocument();
  });

  it('renders tasks after loading', async () => {
    render(<TaskList onSelect={mockOnSelect} />);

    await waitFor(() => {
      expect(screen.getByText('task-uuid-1')).toBeInTheDocument();
      expect(screen.getByText('task-uuid-2')).toBeInTheDocument();
      expect(screen.getByText('task-uuid-3')).toBeInTheDocument();
    });
  });

  it('displays task status badges', async () => {
    render(<TaskList onSelect={mockOnSelect} />);

    await waitFor(() => {
      expect(screen.getByText('completed')).toBeInTheDocument();
      expect(screen.getByText('active')).toBeInTheDocument();
      expect(screen.getByText('failed')).toBeInTheDocument();
    });
  });

  it('shows from and to agents', async () => {
    render(<TaskList onSelect={mockOnSelect} />);

    await waitFor(() => {
      expect(screen.getAllByText('Agent A').length).toBeGreaterThan(0);
      expect(screen.getAllByText('Agent B').length).toBeGreaterThan(0);
    });
  });

  it('calls onSelect when task row clicked', async () => {
    render(<TaskList onSelect={mockOnSelect} />);

    await waitFor(() => {
      expect(screen.getByText('task-uuid-1')).toBeInTheDocument();
    });

    fireEvent.click(screen.getByText('task-uuid-1'));

    expect(mockOnSelect).toHaveBeenCalledWith(mockTasks[0]);
  });

  it('filters by status', async () => {
    render(<TaskList onSelect={mockOnSelect} />);

    await waitFor(() => {
      expect(screen.getByText('task-uuid-1')).toBeInTheDocument();
    });

    const statusFilter = screen.getByLabelText(/status/i);
    fireEvent.change(statusFilter, { target: { value: 'completed' } });

    await waitFor(() => {
      expect(a2aTasksApiService.getTasks).toHaveBeenCalledWith(
        expect.objectContaining({ status: 'completed' })
      );
    });
  });

  it('filters by from_agent_id', async () => {
    render(<TaskList onSelect={mockOnSelect} />);

    await waitFor(() => {
      expect(screen.getByText('task-uuid-1')).toBeInTheDocument();
    });

    const agentFilter = screen.getByLabelText(/from agent/i);
    fireEvent.change(agentFilter, { target: { value: 'agent-1' } });

    await waitFor(() => {
      expect(a2aTasksApiService.getTasks).toHaveBeenCalledWith(
        expect.objectContaining({ from_agent_id: 'agent-1' })
      );
    });
  });

  it('displays empty state when no tasks', async () => {
    (a2aTasksApiService.getTasks as jest.Mock).mockResolvedValue({
      items: [],
      pagination: { current_page: 1, total_count: 0, total_pages: 0 },
    });

    render(<TaskList onSelect={mockOnSelect} />);

    await waitFor(() => {
      expect(screen.getByText(/no tasks/i)).toBeInTheDocument();
    });
  });

  it('shows error message for failed tasks', async () => {
    render(<TaskList onSelect={mockOnSelect} />);

    await waitFor(() => {
      expect(screen.getByText(/timed out/i)).toBeInTheDocument();
    });
  });

  it('shows duration for completed tasks', async () => {
    render(<TaskList onSelect={mockOnSelect} />);

    await waitFor(() => {
      // Should calculate and show duration
      expect(screen.getByText(/4s|4 seconds/i)).toBeInTheDocument();
    });
  });

  it('refreshes list when refresh button clicked', async () => {
    render(<TaskList onSelect={mockOnSelect} />);

    await waitFor(() => {
      expect(screen.getByText('task-uuid-1')).toBeInTheDocument();
    });

    const refreshButton = screen.getByRole('button', { name: /refresh/i });
    fireEvent.click(refreshButton);

    await waitFor(() => {
      expect(a2aTasksApiService.getTasks).toHaveBeenCalledTimes(2);
    });
  });
});

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
      task_id: 'task-uuid-1111-2222-3333',
      status: 'completed',
      from_agent_id: 'agent-1-id',
      to_agent_id: 'agent-2-id',
      created_at: '2025-01-15T10:00:00Z',
      started_at: '2025-01-15T10:00:01Z',
      completed_at: '2025-01-15T10:00:05Z',
    },
    {
      id: '2',
      task_id: 'task-uuid-4444-5555-6666',
      status: 'active',
      from_agent_id: 'agent-1-id',
      to_agent_id: 'agent-3-id',
      created_at: '2025-01-15T11:00:00Z',
      started_at: '2025-01-15T11:00:01Z',
    },
    {
      id: '3',
      task_id: 'task-uuid-7777-8888-9999',
      status: 'failed',
      from_agent_id: 'agent-2-id',
      to_agent_id: 'agent-1-id',
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

    render(<TaskList onSelectTask={mockOnSelect} />);

    expect(screen.getByText(/loading/i)).toBeInTheDocument();
  });

  it('renders tasks after loading', async () => {
    render(<TaskList onSelectTask={mockOnSelect} />);

    // Wait for tasks to load by checking for duration text (which proves tasks rendered)
    await waitFor(() => {
      expect(screen.getByText(/Duration: 4/)).toBeInTheDocument();
    });

    // Also verify we can find the status count text
    await waitFor(() => {
      expect(screen.getByText(/3 of 3 tasks/)).toBeInTheDocument();
    });
  });

  it('displays task status badges', async () => {
    render(<TaskList onSelectTask={mockOnSelect} />);

    await waitFor(() => {
      // Status text appears in both filter options and badges
      expect(screen.getAllByText('Completed').length).toBeGreaterThanOrEqual(1);
      expect(screen.getAllByText('Active').length).toBeGreaterThanOrEqual(1);
      expect(screen.getAllByText('Failed').length).toBeGreaterThanOrEqual(1);
    });
  });

  it('calls onSelect when task card clicked', async () => {
    render(<TaskList onSelectTask={mockOnSelect} />);

    // Wait for content to load
    await waitFor(() => {
      expect(screen.getByText(/Duration: 4/)).toBeInTheDocument();
    });

    // Find the Completed badge in the task card (not in the filter dropdown)
    const completedBadges = screen.getAllByText('Completed');
    // The badge in the card should be the second one (first is in dropdown)
    const badgeInCard = completedBadges.find(el => el.tagName === 'SPAN');
    if (badgeInCard) {
      const card = badgeInCard.closest('[class*="cursor-pointer"]');
      if (card) {
        fireEvent.click(card);
      }
    }

    expect(mockOnSelect).toHaveBeenCalledWith(mockTasks[0]);
  });

  it('filters by status', async () => {
    render(<TaskList onSelectTask={mockOnSelect} />);

    await waitFor(() => {
      expect(screen.getAllByText('Completed').length).toBeGreaterThanOrEqual(1);
    });

    // Find and change the status select
    const statusSelect = screen.getByRole('combobox');
    fireEvent.change(statusSelect, { target: { value: 'completed' } });

    await waitFor(() => {
      expect(a2aTasksApiService.getTasks).toHaveBeenCalledWith(
        expect.objectContaining({ status: 'completed' })
      );
    });
  });

  it('displays empty state when no tasks', async () => {
    (a2aTasksApiService.getTasks as jest.Mock).mockResolvedValue({
      items: [],
      pagination: { current_page: 1, total_count: 0, total_pages: 0 },
    });

    render(<TaskList onSelectTask={mockOnSelect} />);

    await waitFor(() => {
      expect(screen.getByText(/no a2a tasks/i)).toBeInTheDocument();
    });
  });

  it('shows error message for failed tasks', async () => {
    render(<TaskList onSelectTask={mockOnSelect} />);

    await waitFor(() => {
      expect(screen.getByText(/timed out/i)).toBeInTheDocument();
    });
  });

  it('shows duration for completed tasks', async () => {
    render(<TaskList onSelectTask={mockOnSelect} />);

    await waitFor(() => {
      // Duration is 4 seconds
      expect(screen.getByText(/Duration: 4/)).toBeInTheDocument();
    });
  });

  it('refreshes list when refresh button clicked', async () => {
    render(<TaskList onSelectTask={mockOnSelect} />);

    await waitFor(() => {
      expect(screen.getAllByText('Completed').length).toBeGreaterThanOrEqual(1);
    });

    const refreshButton = screen.getByRole('button', { name: /refresh/i });
    fireEvent.click(refreshButton);

    await waitFor(() => {
      expect(a2aTasksApiService.getTasks).toHaveBeenCalledTimes(2);
    });
  });

  it('allows search by task ID', async () => {
    render(<TaskList onSelectTask={mockOnSelect} />);

    await waitFor(() => {
      expect(screen.getAllByText('Completed').length).toBeGreaterThanOrEqual(1);
    });

    const searchInput = screen.getByPlaceholderText(/search/i);
    fireEvent.change(searchInput, { target: { value: 'task-uuid-1111' } });

    // After filtering, the Failed badge in cards should be hidden
    // But "Failed" in dropdown option still exists
    await waitFor(() => {
      // Count should decrease from 2 (dropdown + card) to 1 (dropdown only)
      const failedElements = screen.getAllByText('Failed');
      // Only the dropdown option should remain
      expect(failedElements.length).toBe(1);
      expect(failedElements[0].tagName).toBe('OPTION');
    });
  });
});

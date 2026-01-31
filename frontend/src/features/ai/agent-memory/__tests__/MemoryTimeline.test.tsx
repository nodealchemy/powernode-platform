import { render, screen, waitFor, fireEvent } from '@testing-library/react';
import { MemoryTimeline } from '../components/MemoryTimeline';
import { memoryApiService } from '@/shared/services/ai';

// Mock the API service
jest.mock('@/shared/services/ai', () => ({
  memoryApiService: {
    getAgentMemories: jest.fn(),
    searchMemories: jest.fn(),
  },
}));

// Mock useNotifications hook
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({
    addNotification: jest.fn(),
  }),
}));

describe('MemoryTimeline', () => {
  const mockMemories = [
    {
      id: '1',
      entry_key: 'user_name',
      memory_type: 'factual',
      content: { text: 'John Doe' },
      importance_score: 1.0,
      confidence_score: 1.0,
      created_at: '2025-01-15T10:00:00Z',
    },
    {
      id: '2',
      entry_key: 'exp_abc123',
      memory_type: 'experiential',
      content: { text: 'User prefers dark mode' },
      importance_score: 0.7,
      confidence_score: 0.8,
      outcome_success: true,
      context_tags: ['preferences'],
      created_at: '2025-01-14T15:30:00Z',
    },
    {
      id: '3',
      entry_key: 'task_state',
      memory_type: 'working',
      content: { step: 2, status: 'processing' },
      importance_score: 0.5,
      created_at: '2025-01-15T11:00:00Z',
    },
  ];

  beforeEach(() => {
    jest.clearAllMocks();
    (memoryApiService.getAgentMemories as jest.Mock).mockResolvedValue({
      memories: mockMemories,
      pagination: { current_page: 1, total_count: 3, total_pages: 1 },
    });
  });

  it('renders loading state initially', () => {
    (memoryApiService.getAgentMemories as jest.Mock).mockImplementation(
      () => new Promise(() => {})
    );

    render(<MemoryTimeline agentId="agent-1" />);

    expect(screen.getByText(/loading/i)).toBeInTheDocument();
  });

  it('renders memories grouped by date', async () => {
    render(<MemoryTimeline agentId="agent-1" />);

    await waitFor(() => {
      expect(screen.getByText(/john doe/i)).toBeInTheDocument();
      expect(screen.getByText(/dark mode/i)).toBeInTheDocument();
    });
  });

  it('displays memory type badges', async () => {
    render(<MemoryTimeline agentId="agent-1" />);

    await waitFor(() => {
      expect(screen.getByText(/factual/i)).toBeInTheDocument();
      expect(screen.getByText(/experiential/i)).toBeInTheDocument();
      expect(screen.getByText(/working/i)).toBeInTheDocument();
    });
  });

  it('filters by memory type', async () => {
    render(<MemoryTimeline agentId="agent-1" />);

    await waitFor(() => {
      expect(screen.getByText(/john doe/i)).toBeInTheDocument();
    });

    const typeFilter = screen.getByLabelText(/type/i);
    fireEvent.change(typeFilter, { target: { value: 'factual' } });

    await waitFor(() => {
      expect(memoryApiService.getAgentMemories).toHaveBeenCalledWith(
        'agent-1',
        expect.objectContaining({ memory_type: 'factual' })
      );
    });
  });

  it('filters by date range', async () => {
    render(<MemoryTimeline agentId="agent-1" />);

    await waitFor(() => {
      expect(screen.getByText(/john doe/i)).toBeInTheDocument();
    });

    const dateFilter = screen.getByLabelText(/date range/i);
    fireEvent.change(dateFilter, { target: { value: 'last_7_days' } });

    await waitFor(() => {
      expect(memoryApiService.getAgentMemories).toHaveBeenCalled();
    });
  });

  it('shows importance score for memories', async () => {
    render(<MemoryTimeline agentId="agent-1" />);

    await waitFor(() => {
      expect(screen.getByText(/100%/)).toBeInTheDocument(); // importance 1.0
      expect(screen.getByText(/70%/)).toBeInTheDocument(); // importance 0.7
    });
  });

  it('shows outcome indicator for experiential memories', async () => {
    render(<MemoryTimeline agentId="agent-1" />);

    await waitFor(() => {
      expect(screen.getByText(/success/i)).toBeInTheDocument();
    });
  });

  it('shows tags for memories', async () => {
    render(<MemoryTimeline agentId="agent-1" />);

    await waitFor(() => {
      expect(screen.getByText('preferences')).toBeInTheDocument();
    });
  });

  it('displays empty state when no memories', async () => {
    (memoryApiService.getAgentMemories as jest.Mock).mockResolvedValue({
      memories: [],
      pagination: { current_page: 1, total_count: 0, total_pages: 0 },
    });

    render(<MemoryTimeline agentId="agent-1" />);

    await waitFor(() => {
      expect(screen.getByText(/no memories/i)).toBeInTheDocument();
    });
  });
});

import { render, screen, waitFor, fireEvent } from '@testing-library/react';
import { MemoryTimeline } from '../components/MemoryTimeline';
import { memoryApiService } from '@/shared/services/ai';

// Mock the API service
jest.mock('@/shared/services/ai', () => ({
  memoryApiService: {
    getMemories: jest.fn(),
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
      memory_type: 'factual' as const,
      content: { text: 'John Doe' },
      content_text: 'John Doe',
      importance_score: 1.0,
      confidence_score: 1.0,
      access_count: 5,
      created_at: '2025-01-15T10:00:00Z',
      updated_at: '2025-01-15T10:00:00Z',
    },
    {
      id: '2',
      entry_key: 'exp_abc123',
      memory_type: 'experiential' as const,
      content: { text: 'User prefers dark mode' },
      content_text: 'User prefers dark mode',
      importance_score: 0.7,
      confidence_score: 0.8,
      outcome_success: true,
      context_tags: ['preferences'],
      access_count: 3,
      created_at: '2025-01-14T15:30:00Z',
      updated_at: '2025-01-14T15:30:00Z',
    },
    {
      id: '3',
      entry_key: 'task_state',
      memory_type: 'working' as const,
      content: { step: 2, status: 'processing' },
      importance_score: 0.5,
      access_count: 0,
      created_at: '2025-01-15T11:00:00Z',
      updated_at: '2025-01-15T11:00:00Z',
    },
  ];

  beforeEach(() => {
    jest.clearAllMocks();
    (memoryApiService.getMemories as jest.Mock).mockResolvedValue({
      items: mockMemories,
      pagination: { current_page: 1, total_count: 3, total_pages: 1 },
    });
  });

  it('renders loading state initially', () => {
    (memoryApiService.getMemories as jest.Mock).mockImplementation(
      () => new Promise(() => {})
    );

    render(<MemoryTimeline agentId="agent-1" />);

    expect(screen.getByText(/loading/i)).toBeInTheDocument();
  });

  it('renders memories after loading', async () => {
    render(<MemoryTimeline agentId="agent-1" />);

    await waitFor(() => {
      expect(screen.getByText(/john doe/i)).toBeInTheDocument();
      expect(screen.getByText(/dark mode/i)).toBeInTheDocument();
    });
  });

  it('displays memory type badges', async () => {
    render(<MemoryTimeline agentId="agent-1" />);

    await waitFor(() => {
      // Check for badge text - may appear multiple times (in filter and cards)
      expect(screen.getAllByText('Factual').length).toBeGreaterThan(0);
      expect(screen.getAllByText('Experiential').length).toBeGreaterThan(0);
      expect(screen.getAllByText('Working').length).toBeGreaterThan(0);
    });
  });

  it('filters by memory type', async () => {
    render(<MemoryTimeline agentId="agent-1" />);

    await waitFor(() => {
      expect(screen.getByText(/john doe/i)).toBeInTheDocument();
    });

    // Find the type filter dropdown
    const typeFilter = screen.getAllByRole('combobox')[0];
    fireEvent.change(typeFilter, { target: { value: 'factual' } });

    await waitFor(() => {
      expect(memoryApiService.getMemories).toHaveBeenCalledWith(
        'agent-1',
        expect.objectContaining({ memory_type: 'factual' })
      );
    });
  });

  it('shows importance score for memories', async () => {
    render(<MemoryTimeline agentId="agent-1" />);

    await waitFor(() => {
      expect(screen.getByText(/Importance: 100%/)).toBeInTheDocument(); // importance 1.0
      expect(screen.getByText(/Importance: 70%/)).toBeInTheDocument(); // importance 0.7
    });
  });

  it('shows tags for memories', async () => {
    render(<MemoryTimeline agentId="agent-1" />);

    await waitFor(() => {
      expect(screen.getByText('preferences')).toBeInTheDocument();
    });
  });

  it('displays empty state when no memories', async () => {
    (memoryApiService.getMemories as jest.Mock).mockResolvedValue({
      items: [],
      pagination: { current_page: 1, total_count: 0, total_pages: 0 },
    });

    render(<MemoryTimeline agentId="agent-1" />);

    await waitFor(() => {
      expect(screen.getByText(/no memories found/i)).toBeInTheDocument();
    });
  });

  it('shows memory entry keys', async () => {
    render(<MemoryTimeline agentId="agent-1" />);

    await waitFor(() => {
      expect(screen.getByText('user_name')).toBeInTheDocument();
      expect(screen.getByText('exp_abc123')).toBeInTheDocument();
      expect(screen.getByText('task_state')).toBeInTheDocument();
    });
  });

  it('allows semantic search', async () => {
    (memoryApiService.searchMemories as jest.Mock).mockResolvedValue({
      results: [mockMemories[0]],
    });

    render(<MemoryTimeline agentId="agent-1" />);

    await waitFor(() => {
      expect(screen.getByText(/john doe/i)).toBeInTheDocument();
    });

    const searchInput = screen.getByPlaceholderText(/semantic search/i);
    fireEvent.change(searchInput, { target: { value: 'user name' } });
    fireEvent.keyDown(searchInput, { key: 'Enter' });

    await waitFor(() => {
      expect(memoryApiService.searchMemories).toHaveBeenCalledWith(
        'agent-1',
        expect.objectContaining({ query: 'user name' })
      );
    });
  });

  it('refreshes list when refresh button clicked', async () => {
    render(<MemoryTimeline agentId="agent-1" />);

    await waitFor(() => {
      expect(screen.getByText(/john doe/i)).toBeInTheDocument();
    });

    const refreshButton = screen.getByRole('button', { name: /refresh/i });
    fireEvent.click(refreshButton);

    await waitFor(() => {
      expect(memoryApiService.getMemories).toHaveBeenCalledTimes(2);
    });
  });

  it('shows access count for memories', async () => {
    render(<MemoryTimeline agentId="agent-1" />);

    await waitFor(() => {
      expect(screen.getByText(/5 accesses/)).toBeInTheDocument();
      expect(screen.getByText(/3 accesses/)).toBeInTheDocument();
    });
  });

  it('calls onSelectMemory when memory is clicked', async () => {
    const mockOnSelect = jest.fn();
    render(<MemoryTimeline agentId="agent-1" onSelectMemory={mockOnSelect} />);

    await waitFor(() => {
      expect(screen.getByText('user_name')).toBeInTheDocument();
    });

    // Click on the memory card containing user_name
    const memoryCard = screen.getByText('user_name').closest('[class*="cursor-pointer"]');
    if (memoryCard) {
      fireEvent.click(memoryCard);
    }

    expect(mockOnSelect).toHaveBeenCalledWith(mockMemories[0]);
  });
});

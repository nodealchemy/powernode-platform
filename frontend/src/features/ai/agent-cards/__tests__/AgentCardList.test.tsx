import { render, screen, waitFor, fireEvent } from '@testing-library/react';
import { AgentCardList } from '../components/AgentCardList';
import { agentCardsApiService } from '@/shared/services/ai';

// Mock the API service
jest.mock('@/shared/services/ai', () => ({
  agentCardsApiService: {
    getAgentCards: jest.fn(),
  },
}));

// Mock useNotifications hook
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({
    addNotification: jest.fn(),
  }),
}));

describe('AgentCardList', () => {
  const mockAgentCards = [
    {
      id: '1',
      name: 'Test Agent 1',
      description: 'A test agent for summarization',
      status: 'active',
      visibility: 'private',
      capabilities: {
        skills: [{ id: 'summarize', name: 'Summarize' }],
      },
      task_count: 10,
      success_count: 8,
      created_at: '2025-01-01T00:00:00Z',
      updated_at: '2025-01-15T00:00:00Z',
    },
    {
      id: '2',
      name: 'Test Agent 2',
      description: 'A test agent for translation',
      status: 'active',
      visibility: 'public',
      capabilities: {
        skills: [{ id: 'translate', name: 'Translate' }],
      },
      task_count: 5,
      success_count: 5,
      created_at: '2025-01-02T00:00:00Z',
      updated_at: '2025-01-16T00:00:00Z',
    },
  ];

  const mockOnSelect = jest.fn();

  beforeEach(() => {
    jest.clearAllMocks();
    (agentCardsApiService.getAgentCards as jest.Mock).mockResolvedValue({
      items: mockAgentCards,
      pagination: { current_page: 1, total_count: 2, total_pages: 1 },
    });
  });

  it('renders loading state initially', () => {
    (agentCardsApiService.getAgentCards as jest.Mock).mockImplementation(
      () => new Promise(() => {}) // Never resolves
    );

    render(<AgentCardList onSelectCard={mockOnSelect} />);

    expect(screen.getByText(/loading/i)).toBeInTheDocument();
  });

  it('renders agent cards after loading', async () => {
    render(<AgentCardList onSelectCard={mockOnSelect} />);

    await waitFor(() => {
      expect(screen.getByText('Test Agent 1')).toBeInTheDocument();
      expect(screen.getByText('Test Agent 2')).toBeInTheDocument();
    });
  });

  it('shows agent descriptions', async () => {
    render(<AgentCardList onSelectCard={mockOnSelect} />);

    await waitFor(() => {
      expect(screen.getByText(/summarization/i)).toBeInTheDocument();
      expect(screen.getByText(/translation/i)).toBeInTheDocument();
    });
  });

  it('calls onSelect when card is clicked', async () => {
    render(<AgentCardList onSelectCard={mockOnSelect} />);

    await waitFor(() => {
      expect(screen.getByText('Test Agent 1')).toBeInTheDocument();
    });

    // Click on the card
    const card = screen.getByText('Test Agent 1').closest('[class*="cursor-pointer"]');
    if (card) {
      fireEvent.click(card);
    } else {
      fireEvent.click(screen.getByText('Test Agent 1'));
    }

    expect(mockOnSelect).toHaveBeenCalledWith(mockAgentCards[0]);
  });

  it('displays empty state when no cards found', async () => {
    (agentCardsApiService.getAgentCards as jest.Mock).mockResolvedValue({
      items: [],
      pagination: { current_page: 1, total_count: 0, total_pages: 0 },
    });

    render(<AgentCardList onSelectCard={mockOnSelect} />);

    await waitFor(() => {
      expect(screen.getByText(/no agent cards/i)).toBeInTheDocument();
    });
  });

  it('displays error state on fetch failure', async () => {
    (agentCardsApiService.getAgentCards as jest.Mock).mockRejectedValue(
      new Error('Failed to fetch')
    );

    render(<AgentCardList onSelectCard={mockOnSelect} />);

    await waitFor(() => {
      expect(screen.getByText(/error|failed/i)).toBeInTheDocument();
    });
  });

  it('shows skill badges for each card', async () => {
    render(<AgentCardList onSelectCard={mockOnSelect} />);

    await waitFor(() => {
      expect(screen.getByText('Summarize')).toBeInTheDocument();
      expect(screen.getByText('Translate')).toBeInTheDocument();
    });
  });
});

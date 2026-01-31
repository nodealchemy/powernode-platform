import { render, screen, waitFor, fireEvent } from '@testing-library/react';
import { AgentCardDetail } from '../components/AgentCardDetail';
import { agentCardsApiService } from '@/shared/services/ai';

// Mock the API service
jest.mock('@/shared/services/ai', () => ({
  agentCardsApiService: {
    getAgentCard: jest.fn(),
    publishAgentCard: jest.fn(),
    deprecateAgentCard: jest.fn(),
    refreshAgentCardMetrics: jest.fn(),
  },
}));

// Mock useNotifications hook
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({
    addNotification: jest.fn(),
  }),
}));

describe('AgentCardDetail', () => {
  const mockAgentCard = {
    id: '1',
    name: 'Test Agent',
    description: 'A comprehensive test agent',
    status: 'draft',
    visibility: 'private',
    protocol_version: '0.3',
    capabilities: {
      skills: [
        { id: 'summarize', name: 'Summarize', description: 'Summarize documents' },
        { id: 'translate', name: 'Translate', description: 'Translate text' },
      ],
    },
    authentication: { schemes: ['bearer'] },
    task_count: 50,
    success_count: 45,
    failure_count: 5,
    avg_duration_ms: 1200,
    provider_name: 'Test Provider',
    documentation_url: 'https://docs.example.com',
    created_at: '2025-01-01T00:00:00Z',
    updated_at: '2025-01-15T00:00:00Z',
  };

  const mockOnBack = jest.fn();
  const mockOnEdit = jest.fn();

  beforeEach(() => {
    jest.clearAllMocks();
    (agentCardsApiService.getAgentCard as jest.Mock).mockResolvedValue({
      agent_card: mockAgentCard,
    });
  });

  it('renders loading state initially', () => {
    (agentCardsApiService.getAgentCard as jest.Mock).mockImplementation(
      () => new Promise(() => {})
    );

    render(
      <AgentCardDetail agentCardId="1" onBack={mockOnBack} onEdit={mockOnEdit} />
    );

    expect(screen.getByText(/loading/i)).toBeInTheDocument();
  });

  it('renders agent card details after loading', async () => {
    render(
      <AgentCardDetail agentCardId="1" onBack={mockOnBack} onEdit={mockOnEdit} />
    );

    await waitFor(() => {
      expect(screen.getByText('Test Agent')).toBeInTheDocument();
      expect(screen.getByText('A comprehensive test agent')).toBeInTheDocument();
    });
  });

  it('displays all skills', async () => {
    render(
      <AgentCardDetail agentCardId="1" onBack={mockOnBack} onEdit={mockOnEdit} />
    );

    await waitFor(() => {
      expect(screen.getByText('Summarize')).toBeInTheDocument();
      expect(screen.getByText('Translate')).toBeInTheDocument();
    });
  });

  it('displays metrics', async () => {
    render(
      <AgentCardDetail agentCardId="1" onBack={mockOnBack} onEdit={mockOnEdit} />
    );

    await waitFor(() => {
      expect(screen.getByText(/50/)).toBeInTheDocument(); // task_count
      expect(screen.getByText(/90%/)).toBeInTheDocument(); // success rate
    });
  });

  it('shows publish button for draft cards', async () => {
    render(
      <AgentCardDetail agentCardId="1" onBack={mockOnBack} onEdit={mockOnEdit} />
    );

    await waitFor(() => {
      expect(screen.getByRole('button', { name: /publish/i })).toBeInTheDocument();
    });
  });

  it('calls publish API when publish button clicked', async () => {
    (agentCardsApiService.publishAgentCard as jest.Mock).mockResolvedValue({
      agent_card: { ...mockAgentCard, status: 'published' },
    });

    render(
      <AgentCardDetail agentCardId="1" onBack={mockOnBack} onEdit={mockOnEdit} />
    );

    await waitFor(() => {
      expect(screen.getByRole('button', { name: /publish/i })).toBeInTheDocument();
    });

    fireEvent.click(screen.getByRole('button', { name: /publish/i }));

    await waitFor(() => {
      expect(agentCardsApiService.publishAgentCard).toHaveBeenCalledWith('1');
    });
  });

  it('shows deprecate button for published cards', async () => {
    (agentCardsApiService.getAgentCard as jest.Mock).mockResolvedValue({
      agent_card: { ...mockAgentCard, status: 'published' },
    });

    render(
      <AgentCardDetail agentCardId="1" onBack={mockOnBack} onEdit={mockOnEdit} />
    );

    await waitFor(() => {
      expect(screen.getByRole('button', { name: /deprecate/i })).toBeInTheDocument();
    });
  });

  it('calls onBack when back button clicked', async () => {
    render(
      <AgentCardDetail agentCardId="1" onBack={mockOnBack} onEdit={mockOnEdit} />
    );

    await waitFor(() => {
      expect(screen.getByText('Test Agent')).toBeInTheDocument();
    });

    fireEvent.click(screen.getByRole('button', { name: /back/i }));

    expect(mockOnBack).toHaveBeenCalled();
  });

  it('calls onEdit when edit button clicked', async () => {
    render(
      <AgentCardDetail agentCardId="1" onBack={mockOnBack} onEdit={mockOnEdit} />
    );

    await waitFor(() => {
      expect(screen.getByText('Test Agent')).toBeInTheDocument();
    });

    fireEvent.click(screen.getByRole('button', { name: /edit/i }));

    expect(mockOnEdit).toHaveBeenCalledWith(mockAgentCard);
  });

  it('displays A2A JSON section', async () => {
    render(
      <AgentCardDetail agentCardId="1" onBack={mockOnBack} onEdit={mockOnEdit} />
    );

    await waitFor(() => {
      expect(screen.getByText(/A2A JSON/i)).toBeInTheDocument();
    });
  });
});

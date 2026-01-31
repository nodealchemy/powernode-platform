import { render, screen, waitFor, fireEvent } from '@testing-library/react';
import { ContextInjectionPreview } from '../components/ContextInjectionPreview';
import { memoryApiService } from '@/shared/services/ai';

// Mock the API service
jest.mock('@/shared/services/ai', () => ({
  memoryApiService: {
    previewContextInjection: jest.fn(),
  },
}));

// Mock useNotifications hook
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({
    addNotification: jest.fn(),
  }),
}));

describe('ContextInjectionPreview', () => {
  const mockPreviewResult = {
    preview: '## Known Facts\n- user_name: John Doe\n\n## Relevant Experience\n- [success] User prefers concise responses',
    token_estimate: 150,
    breakdown: {
      factual: 1,
      working: 0,
      experiential: 1,
    },
    within_budget: true,
  };

  beforeEach(() => {
    jest.clearAllMocks();
    (memoryApiService.previewContextInjection as jest.Mock).mockResolvedValue(
      mockPreviewResult
    );
  });

  it('renders the preview tool', () => {
    render(<ContextInjectionPreview agentId="agent-1" />);

    expect(screen.getByText(/context injection preview/i)).toBeInTheDocument();
  });

  it('shows token budget input', () => {
    render(<ContextInjectionPreview agentId="agent-1" />);

    expect(screen.getByLabelText(/token budget/i)).toBeInTheDocument();
  });

  it('shows query input for semantic search', () => {
    render(<ContextInjectionPreview agentId="agent-1" />);

    expect(screen.getByPlaceholderText(/query/i)).toBeInTheDocument();
  });

  it('fetches preview when generate button clicked', async () => {
    render(<ContextInjectionPreview agentId="agent-1" />);

    const generateButton = screen.getByRole('button', { name: /generate/i });
    fireEvent.click(generateButton);

    await waitFor(() => {
      expect(memoryApiService.previewContextInjection).toHaveBeenCalledWith(
        'agent-1',
        expect.any(Object)
      );
    });
  });

  it('displays preview content', async () => {
    render(<ContextInjectionPreview agentId="agent-1" />);

    const generateButton = screen.getByRole('button', { name: /generate/i });
    fireEvent.click(generateButton);

    await waitFor(() => {
      expect(screen.getByText(/known facts/i)).toBeInTheDocument();
    });
  });

  it('shows token estimate', async () => {
    render(<ContextInjectionPreview agentId="agent-1" />);

    const generateButton = screen.getByRole('button', { name: /generate/i });
    fireEvent.click(generateButton);

    await waitFor(() => {
      expect(screen.getByText(/150 tokens/i)).toBeInTheDocument();
    });
  });

  it('shows breakdown by memory type', async () => {
    render(<ContextInjectionPreview agentId="agent-1" />);

    const generateButton = screen.getByRole('button', { name: /generate/i });
    fireEvent.click(generateButton);

    await waitFor(() => {
      expect(screen.getByText(/factual: 1/i)).toBeInTheDocument();
      expect(screen.getByText(/experiential: 1/i)).toBeInTheDocument();
    });
  });

  it('indicates when within budget', async () => {
    render(<ContextInjectionPreview agentId="agent-1" />);

    const generateButton = screen.getByRole('button', { name: /generate/i });
    fireEvent.click(generateButton);

    await waitFor(() => {
      expect(screen.getByText(/within budget/i)).toBeInTheDocument();
    });
  });

  it('indicates when over budget', async () => {
    (memoryApiService.previewContextInjection as jest.Mock).mockResolvedValue({
      ...mockPreviewResult,
      within_budget: false,
      token_estimate: 5000,
    });

    render(<ContextInjectionPreview agentId="agent-1" />);

    const generateButton = screen.getByRole('button', { name: /generate/i });
    fireEvent.click(generateButton);

    await waitFor(() => {
      expect(screen.getByText(/over budget/i)).toBeInTheDocument();
    });
  });

  it('allows changing token budget', async () => {
    render(<ContextInjectionPreview agentId="agent-1" />);

    const budgetInput = screen.getByLabelText(/token budget/i);
    fireEvent.change(budgetInput, { target: { value: '2000' } });

    const generateButton = screen.getByRole('button', { name: /generate/i });
    fireEvent.click(generateButton);

    await waitFor(() => {
      expect(memoryApiService.previewContextInjection).toHaveBeenCalledWith(
        'agent-1',
        expect.objectContaining({ token_budget: 2000 })
      );
    });
  });

  it('includes query in preview request', async () => {
    render(<ContextInjectionPreview agentId="agent-1" />);

    const queryInput = screen.getByPlaceholderText(/query/i);
    fireEvent.change(queryInput, { target: { value: 'user preferences' } });

    const generateButton = screen.getByRole('button', { name: /generate/i });
    fireEvent.click(generateButton);

    await waitFor(() => {
      expect(memoryApiService.previewContextInjection).toHaveBeenCalledWith(
        'agent-1',
        expect.objectContaining({ query: 'user preferences' })
      );
    });
  });
});

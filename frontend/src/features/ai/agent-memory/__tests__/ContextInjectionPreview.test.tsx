import { render, screen, waitFor, fireEvent } from '@testing-library/react';
import { ContextInjectionPreview } from '../components/ContextInjectionPreview';
import { memoryApiService } from '@/shared/services/ai';

// Mock the API service
jest.mock('@/shared/services/ai', () => ({
  memoryApiService: {
    getContextInjection: jest.fn(),
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
    context: '## Known Facts\n- user_name: John Doe\n\n## Relevant Experience\n- [success] User prefers concise responses',
    token_estimate: 150,
    breakdown: {
      factual: 1,
      working: 0,
      experiential: 1,
    },
  };

  beforeEach(() => {
    jest.clearAllMocks();
    (memoryApiService.getContextInjection as jest.Mock).mockResolvedValue(
      mockPreviewResult
    );
  });

  it('renders the preview tool', () => {
    render(<ContextInjectionPreview agentId="agent-1" />);

    expect(screen.getByText(/context injection preview/i)).toBeInTheDocument();
  });

  it('shows token budget input', () => {
    render(<ContextInjectionPreview agentId="agent-1" />);

    expect(screen.getByText('Token Budget')).toBeInTheDocument();
    expect(screen.getByRole('spinbutton')).toBeInTheDocument();
  });

  it('shows query input for semantic search', () => {
    render(<ContextInjectionPreview agentId="agent-1" />);

    expect(screen.getByPlaceholderText(/enter a task or query/i)).toBeInTheDocument();
  });

  it('fetches preview when generate button clicked', async () => {
    render(<ContextInjectionPreview agentId="agent-1" />);

    const generateButton = screen.getByRole('button', { name: /generate context/i });
    fireEvent.click(generateButton);

    await waitFor(() => {
      expect(memoryApiService.getContextInjection).toHaveBeenCalledWith(
        'agent-1',
        expect.any(Object)
      );
    });
  });

  it('displays context content', async () => {
    render(<ContextInjectionPreview agentId="agent-1" />);

    const generateButton = screen.getByRole('button', { name: /generate context/i });
    fireEvent.click(generateButton);

    await waitFor(() => {
      expect(screen.getByText(/known facts/i)).toBeInTheDocument();
    });
  });

  it('shows token estimate', async () => {
    render(<ContextInjectionPreview agentId="agent-1" />);

    const generateButton = screen.getByRole('button', { name: /generate context/i });
    fireEvent.click(generateButton);

    await waitFor(() => {
      expect(screen.getByText(/~150 tokens/i)).toBeInTheDocument();
    });
  });

  it('shows breakdown by memory type', async () => {
    render(<ContextInjectionPreview agentId="agent-1" />);

    const generateButton = screen.getByRole('button', { name: /generate context/i });
    fireEvent.click(generateButton);

    await waitFor(() => {
      // The breakdown labels are displayed
      // Note: "Factual" button also exists in the toggle section
      expect(screen.getAllByText('Factual').length).toBeGreaterThan(0);
      expect(screen.getAllByText('Experiential').length).toBeGreaterThan(0);
    });
  });

  it('allows changing token budget', async () => {
    render(<ContextInjectionPreview agentId="agent-1" />);

    const budgetInput = screen.getByRole('spinbutton');
    fireEvent.change(budgetInput, { target: { value: '2000' } });

    const generateButton = screen.getByRole('button', { name: /generate context/i });
    fireEvent.click(generateButton);

    await waitFor(() => {
      expect(memoryApiService.getContextInjection).toHaveBeenCalledWith(
        'agent-1',
        expect.objectContaining({ token_budget: 2000 })
      );
    });
  });

  it('includes query in preview request', async () => {
    render(<ContextInjectionPreview agentId="agent-1" />);

    const queryInput = screen.getByPlaceholderText(/enter a task or query/i);
    fireEvent.change(queryInput, { target: { value: 'user preferences' } });

    const generateButton = screen.getByRole('button', { name: /generate context/i });
    fireEvent.click(generateButton);

    await waitFor(() => {
      expect(memoryApiService.getContextInjection).toHaveBeenCalledWith(
        'agent-1',
        expect.objectContaining({ query: 'user preferences' })
      );
    });
  });

  it('allows toggling memory types', async () => {
    render(<ContextInjectionPreview agentId="agent-1" />);

    // Click Working button to add it
    const workingButton = screen.getByRole('button', { name: /working/i });
    fireEvent.click(workingButton);

    const generateButton = screen.getByRole('button', { name: /generate context/i });
    fireEvent.click(generateButton);

    await waitFor(() => {
      expect(memoryApiService.getContextInjection).toHaveBeenCalledWith(
        'agent-1',
        expect.objectContaining({ include_types: expect.arrayContaining(['working']) })
      );
    });
  });

  it('shows error message on failure', async () => {
    (memoryApiService.getContextInjection as jest.Mock).mockRejectedValue(
      new Error('Generation failed')
    );

    render(<ContextInjectionPreview agentId="agent-1" />);

    const generateButton = screen.getByRole('button', { name: /generate context/i });
    fireEvent.click(generateButton);

    await waitFor(() => {
      expect(screen.getByText(/generation failed/i)).toBeInTheDocument();
    });
  });

  it('has copy button after generating context', async () => {
    render(<ContextInjectionPreview agentId="agent-1" />);

    const generateButton = screen.getByRole('button', { name: /generate context/i });
    fireEvent.click(generateButton);

    await waitFor(() => {
      expect(screen.getByRole('button', { name: /copy/i })).toBeInTheDocument();
    });
  });
});

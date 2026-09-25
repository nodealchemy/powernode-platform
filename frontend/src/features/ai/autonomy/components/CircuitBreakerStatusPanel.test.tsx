import { render, screen, fireEvent, waitFor, within } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

// The panel itself is rendered for real — only the HTTP layer (apiClient) and
// the permission check are mocked. fc-42 review fix: proves the reset control
// is gated on ai.autonomy.manage (the endpoint's own permission — was
// previously ungated) and confirms before firing, not against a stubbed panel.

let mockAllowed: string[] = [];
const mockGet = jest.fn();
const mockPost = jest.fn();

jest.mock('@/shared/hooks/usePermissions', () => ({
  usePermissions: () => ({ hasPermission: (p: string) => mockAllowed.includes(p) }),
}));
jest.mock('@/shared/services/apiClient', () => ({
  apiClient: {
    get: (...args: unknown[]) => mockGet(...args),
    post: (...args: unknown[]) => mockPost(...args),
  },
}));
jest.mock('@/shared/components/entity', () => ({
  EntityLink: ({ label }: { label?: string }) => <span>{label}</span>,
}));

import { CircuitBreakerStatusPanel } from './CircuitBreakerStatusPanel';

const breaker = (overrides: Record<string, unknown> = {}) => ({
  id: 'cb-1',
  agent_id: 'agent-1',
  agent_name: 'Researcher',
  action_type: 'web_search',
  state: 'open',
  failure_count: 5,
  success_count: 0,
  failure_threshold: 5,
  success_threshold: 3,
  cooldown_seconds: 60,
  history: [],
  ...overrides,
});

function renderPanel() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <CircuitBreakerStatusPanel />
    </QueryClientProvider>,
  );
}

describe('CircuitBreakerStatusPanel', () => {
  beforeEach(() => {
    mockAllowed = ['ai.autonomy.manage'];
    mockGet.mockReset();
    mockPost.mockReset();
  });

  it('shows an empty state when no breakers are registered', async () => {
    mockGet.mockResolvedValue({ data: { data: [] } });
    renderPanel();
    expect(await screen.findByText('No circuit breakers registered')).toBeInTheDocument();
  });

  it('offers no reset control on a closed breaker', async () => {
    mockGet.mockResolvedValue({ data: { data: [breaker({ state: 'closed' })] } });
    renderPanel();
    await screen.findByText('Researcher');
    expect(screen.queryByTitle('Reset circuit breaker')).not.toBeInTheDocument();
  });

  it('hides the reset control on a tripped breaker without ai.autonomy.manage', async () => {
    mockAllowed = [];
    mockGet.mockResolvedValue({ data: { data: [breaker({ state: 'open' })] } });
    renderPanel();
    await screen.findByText('Researcher');
    expect(screen.queryByTitle('Reset circuit breaker')).not.toBeInTheDocument();
  });

  it('shows the reset control on a tripped breaker with ai.autonomy.manage', async () => {
    mockGet.mockResolvedValue({ data: { data: [breaker({ state: 'open' })] } });
    renderPanel();
    await screen.findByText('Researcher');
    expect(screen.getByTitle('Reset circuit breaker')).toBeInTheDocument();
  });

  it('confirms before resetting, and does not call the API until confirmed', async () => {
    mockGet.mockResolvedValue({ data: { data: [breaker({ state: 'open' })] } });
    mockPost.mockResolvedValue({ data: { data: breaker({ state: 'closed' }) } });
    renderPanel();
    await screen.findByText('Researcher');

    fireEvent.click(screen.getByTitle('Reset circuit breaker'));

    expect(await screen.findByRole('dialog')).toBeInTheDocument();
    expect(mockPost).not.toHaveBeenCalled();

    fireEvent.click(within(screen.getByRole('dialog')).getByRole('button', { name: /reset/i }));

    await waitFor(() => expect(mockPost).toHaveBeenCalledWith('/ai/autonomy/circuit_breakers/cb-1/reset'));
  });

  it('closing the confirmation without confirming never calls the API', async () => {
    mockGet.mockResolvedValue({ data: { data: [breaker({ state: 'open' })] } });
    renderPanel();
    await screen.findByText('Researcher');

    fireEvent.click(screen.getByTitle('Reset circuit breaker'));
    await screen.findByRole('dialog');
    fireEvent.click(within(screen.getByRole('dialog')).getByRole('button', { name: /cancel/i }));

    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument());
    expect(mockPost).not.toHaveBeenCalled();
  });
});

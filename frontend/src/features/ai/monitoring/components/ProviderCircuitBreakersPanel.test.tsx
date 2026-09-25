import { render, screen, fireEvent, waitFor, within } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

let mockAllowed: string[] = [];
const mockGetProviderCircuitBreakers = jest.fn();
const mockResetProviderCircuitBreaker = jest.fn();
const mockAddNotification = jest.fn();

jest.mock('@/shared/hooks/usePermissions', () => ({
  usePermissions: () => ({ hasPermission: (p: string) => mockAllowed.includes(p) }),
}));
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ addNotification: mockAddNotification }),
}));
jest.mock('@/shared/services/ai/MonitoringApiService', () => ({
  monitoringApi: {
    getProviderCircuitBreakers: (...args: unknown[]) => mockGetProviderCircuitBreakers(...args),
    resetProviderCircuitBreaker: (...args: unknown[]) => mockResetProviderCircuitBreaker(...args),
  },
}));

import { ProviderCircuitBreakersPanel } from './ProviderCircuitBreakersPanel';

const breaker = (overrides: Record<string, unknown> = {}) => ({
  service_name: 'openai',
  state: 'closed',
  failure_count: 0,
  success_count: 10,
  consecutive_failures: 0,
  consecutive_successes: 10,
  last_failure_time: null,
  last_success_time: '2026-09-24T10:00:00Z',
  state_changed_at: null,
  next_retry_at: null,
  ...overrides,
});

function renderPanel() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <ProviderCircuitBreakersPanel />
    </QueryClientProvider>,
  );
}

describe('ProviderCircuitBreakersPanel', () => {
  beforeEach(() => {
    mockAllowed = ['ai.monitoring.read', 'ai.monitoring.manage'];
    mockGetProviderCircuitBreakers.mockReset();
    mockResetProviderCircuitBreaker.mockReset();
    mockAddNotification.mockClear();
  });

  it('shows an empty state when no provider breakers are registered', async () => {
    mockGetProviderCircuitBreakers.mockResolvedValue([]);
    renderPanel();
    expect(await screen.findByText('No provider circuit breakers registered')).toBeInTheDocument();
  });

  it('renders each breaker by provider type, tripped ones first, with distinct state labels', async () => {
    mockGetProviderCircuitBreakers.mockResolvedValue([
      breaker({ service_name: 'anthropic', state: 'closed' }),
      breaker({ service_name: 'openai', state: 'open', consecutive_failures: 5 }),
    ]);
    renderPanel();

    const rows = await screen.findAllByText(/openai|anthropic/i);
    expect(rows[0]).toHaveTextContent('openai');
    expect(screen.getByText('Open')).toBeInTheDocument();
    expect(screen.getByText('Closed')).toBeInTheDocument();
  });

  // Mutant proof: a version that reset the WRONG breaker (e.g. always the
  // first in the list) would pass a superficial "reset button works" test.
  // Asserting the exact service_name argument catches that.
  it('confirms, then resets the breaker whose row was clicked — not just any tripped breaker', async () => {
    mockGetProviderCircuitBreakers.mockResolvedValue([
      breaker({ service_name: 'anthropic', state: 'open' }),
      breaker({ service_name: 'openai', state: 'open' }),
    ]);
    mockResetProviderCircuitBreaker.mockResolvedValue(breaker({ service_name: 'openai', state: 'closed' }));
    renderPanel();

    await screen.findByText('openai');
    const resetButtons = screen.getAllByTitle(/Reset .* circuit breaker/);
    const openaiButton = resetButtons.find((btn) => btn.title.includes('openai'));
    expect(openaiButton).toBeTruthy();

    fireEvent.click(openaiButton!);
    const dialog = await screen.findByRole('dialog');
    expect(mockResetProviderCircuitBreaker).not.toHaveBeenCalled();

    fireEvent.click(within(dialog).getByRole('button', { name: /reset/i }));

    await waitFor(() => expect(mockResetProviderCircuitBreaker).toHaveBeenCalledWith('openai'));
    expect(mockResetProviderCircuitBreaker).not.toHaveBeenCalledWith('anthropic');
  });

  it('cancelling the confirmation never calls reset', async () => {
    mockGetProviderCircuitBreakers.mockResolvedValue([breaker({ service_name: 'openai', state: 'open' })]);
    renderPanel();

    await screen.findByText('openai');
    fireEvent.click(screen.getByTitle(/Reset .* circuit breaker/));
    const dialog = await screen.findByRole('dialog');
    fireEvent.click(within(dialog).getByRole('button', { name: /cancel/i }));

    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument());
    expect(mockResetProviderCircuitBreaker).not.toHaveBeenCalled();
  });

  it('shows a toast when the reset fails', async () => {
    mockGetProviderCircuitBreakers.mockResolvedValue([breaker({ service_name: 'openai', state: 'open' })]);
    mockResetProviderCircuitBreaker.mockRejectedValue(new Error('Reset failed: service unavailable'));
    renderPanel();

    await screen.findByText('openai');
    fireEvent.click(screen.getByTitle(/Reset .* circuit breaker/));
    const dialog = await screen.findByRole('dialog');
    fireEvent.click(within(dialog).getByRole('button', { name: /reset/i }));

    await waitFor(() =>
      expect(mockAddNotification).toHaveBeenCalledWith(
        expect.objectContaining({ type: 'error', message: 'Reset failed: service unavailable' }),
      ),
    );
  });

  it('offers no reset button on a closed breaker', async () => {
    mockGetProviderCircuitBreakers.mockResolvedValue([breaker({ service_name: 'openai', state: 'closed' })]);
    renderPanel();
    await screen.findByText('openai');
    expect(screen.queryByTitle(/Reset .* circuit breaker/)).not.toBeInTheDocument();
  });

  // Permission proof: without ai.monitoring.manage the reset control must not
  // render even on a tripped breaker, matching the backend's own gate on
  // MonitoringController#circuit_breaker_reset.
  it('hides the reset control without ai.monitoring.manage, even when tripped', async () => {
    mockAllowed = ['ai.monitoring.read'];
    mockGetProviderCircuitBreakers.mockResolvedValue([breaker({ service_name: 'openai', state: 'open' })]);
    renderPanel();
    await screen.findByText('openai');
    expect(screen.queryByTitle(/Reset .* circuit breaker/)).not.toBeInTheDocument();
  });

  // fc-42 review fix: a fetch failure (403, 500, network) used to fall through
  // to the same "No provider circuit breakers registered" empty state as a
  // genuinely empty, successful response — indistinguishable to the viewer.
  describe('when the fetch fails', () => {
    it('shows an error message, not the empty-state copy', async () => {
      mockGetProviderCircuitBreakers.mockRejectedValue(new Error('Forbidden'));
      renderPanel();

      expect(await screen.findByText('Forbidden')).toBeInTheDocument();
      expect(screen.queryByText('No provider circuit breakers registered')).not.toBeInTheDocument();
    });

    it('retries the fetch when Try Again is clicked', async () => {
      mockGetProviderCircuitBreakers.mockRejectedValueOnce(new Error('Forbidden'));
      mockGetProviderCircuitBreakers.mockResolvedValue([breaker({ service_name: 'openai', state: 'closed' })]);
      renderPanel();

      await screen.findByText('Forbidden');
      fireEvent.click(screen.getByRole('button', { name: /try again/i }));

      await waitFor(() => expect(screen.getByText('openai')).toBeInTheDocument());
      expect(screen.queryByText('Forbidden')).not.toBeInTheDocument();
    });
  });
});

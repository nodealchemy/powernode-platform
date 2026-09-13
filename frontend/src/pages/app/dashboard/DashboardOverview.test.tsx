import { screen, within } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { renderWithProviders } from '@/test-utils';
import { DashboardOverview } from '@/pages/app/dashboard/DashboardOverview';
import type { DashboardStats } from '@/shared/hooks/useDashboardStats';
import type { Verdict } from '@/shared/types/platformStatus';

// M1 review F2 + F4 on the main dashboard's system-health chip and tile. Aimed
// at the reviewer's mutants: e1 (not_measured tone -> success), e2 (the `down`
// row deleted), e3 ("null%" on the chip), e4 (meter guard dropped), e5 (tile
// guard dropped), e6 ("All systems operational" unless down).

const mockUseDashboardStats = jest.fn();
const mockFetchMissions = jest.fn();

jest.mock('@/shared/hooks/useDashboardStats', () => ({
  useDashboardStats: () => mockUseDashboardStats(),
}));
jest.mock('@/shared/hooks/usePageWebSocket', () => ({ usePageWebSocket: () => undefined }));
jest.mock('@/features/missions', () => ({
  useMissions: () => ({ missions: [], loading: false, error: null, fetchMissions: mockFetchMissions }),
}));

const stats = (status: Verdict, score: number | null): DashboardStats => ({
  systemHealth: { status, score },
  overview: { totalExecutionsToday: 0, successRate: 0, avgResponseTime: 0, totalCostToday: 0 },
  agents: { total: 3, active: 2, paused: 1, errored: 0 },
  repositories: 1,
  alerts: [],
});

const renderDashboard = (value: DashboardStats, monitoringError: string | null = null) => {
  mockUseDashboardStats.mockReturnValue({ stats: value, loading: false, error: null, monitoringError, refresh: jest.fn() });
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return renderWithProviders(
    <QueryClientProvider client={client}>
      <DashboardOverview />
    </QueryClientProvider>,
    { preloadedState: { auth: { user: { id: 'u1', name: 'Operator', permissions: [] }, isAuthenticated: true, isLoading: false } } }
  );
};

const healthChip = (): HTMLElement =>
  screen.getByText('System health', { selector: 'button span' }).closest('button') as HTMLElement;
const chipFor = (label: string): HTMLElement =>
  screen.getByText(label, { selector: 'button span' }).closest('button') as HTMLElement;
const tile = (label: string): HTMLElement =>
  screen.getAllByTestId('stat-tile').find((t) => within(t).queryByText(label, { selector: 'h3' })) as HTMLElement;

describe('DashboardOverview — system health', () => {
  it('not measured: a warning chip with a placeholder, "Status: Not measured", no meter — never operational, never "null"', () => {
    const { container } = renderDashboard(stats('not_measured', null));

    const chip = healthChip();
    expect(within(chip).getByText('—')).toBeInTheDocument();
    expect(chip.querySelector('.badge-theme-warning')).not.toBeNull();
    expect(chip.querySelector('.badge-theme-success')).toBeNull();
    // An answered not_measured still shows the agent figures the server sent.
    expect(within(chipFor('Agents active')).getByText('2 of 3')).toBeInTheDocument();

    const health = tile('System health');
    expect(within(health).getByTestId('stat-tile-value')).toHaveTextContent('—');
    expect(within(health).getByTestId('stat-tile-sub')).toHaveTextContent('Status: Not measured');
    expect(within(health).queryByLabelText('System health score')).toBeNull();

    expect(screen.queryByText('All systems operational')).toBeNull();
    expect(container.textContent).not.toMatch(/null/);
  });

  it('degraded: a warning chip with the real score and "Status: Degraded"', () => {
    renderDashboard(stats('degraded', 70));

    expect(within(healthChip()).getByText('70%')).toBeInTheDocument();
    expect(within(tile('System health')).getByTestId('stat-tile-sub')).toHaveTextContent('Status: Degraded');
    expect(screen.queryByText('All systems operational')).toBeNull();
  });

  it('down at a real 0: a danger chip reading 0%, not a placeholder', () => {
    renderDashboard(stats('down', 0));

    const chip = healthChip();
    expect(within(chip).getByText('0%')).toBeInTheDocument();
    expect(chip.querySelector('.badge-theme-danger')).not.toBeNull();
    expect(within(tile('System health')).getByTestId('stat-tile-sub')).toHaveTextContent('Status: Down');
  });

  it('ok: a success chip and "All systems operational" — the only verdict that earns it', () => {
    renderDashboard(stats('ok', 100));

    const chip = healthChip();
    expect(within(chip).getByText('100%')).toBeInTheDocument();
    expect(chip.querySelector('.badge-theme-success')).not.toBeNull();
    expect(within(tile('System health')).getByTestId('stat-tile-sub')).toHaveTextContent('All systems operational');
  });

  it('held: an info chip — blue, as VerdictBadge draws it — never the inert default grey', () => {
    renderDashboard(stats('held', 100));

    const chip = healthChip();
    expect(chip.querySelector('.badge-theme-info')).not.toBeNull();
    expect(chip.querySelector('.badge-theme-default')).toBeNull();
  });

  it('a FAILED read is "Could not load" with the reason — never not_measured, never zeros', () => {
    renderDashboard(stats('not_measured', null), 'Network Error');

    const chip = healthChip();
    expect(within(chip).getByText('Could not load')).toBeInTheDocument();
    expect(chip.querySelector('.badge-theme-warning')).toBeNull();

    const health = tile('System health');
    expect(within(health).getByTestId('stat-tile-sub')).toHaveTextContent('Could not load: Network Error');
    expect(within(health).queryByText(/Not measured/)).toBeNull();

    const executions = tile('Executions today');
    expect(within(executions).getByTestId('stat-tile-value')).toHaveTextContent('—');
    expect(within(executions).getByTestId('stat-tile-sub')).toHaveTextContent('Could not load');
    expect(within(tile('AI agents')).getByTestId('stat-tile-value')).toHaveTextContent('—');
    // The posture chip too (review h5): a failed read is not "2 of 3" agents.
    expect(within(chipFor('Agents active')).getByText('—')).toBeInTheDocument();

    expect(screen.getByRole('alert')).toHaveTextContent('Could not load: Network Error');
    expect(screen.queryByRole('img', { name: /Not measured/ })).toBeNull();
    expect(screen.queryByText('No executions yet')).toBeNull();
  });
});

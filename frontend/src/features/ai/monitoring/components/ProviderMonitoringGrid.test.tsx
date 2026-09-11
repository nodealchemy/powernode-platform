import { screen, within } from '@testing-library/react';
import { renderWithProviders } from '@/test-utils';
import type { ProviderMetrics } from '@/shared/types/monitoring';
import { ProviderMonitoringGrid } from './ProviderMonitoringGrid';

// M1 tail. A provider with no executions has no measured rate: the grid says
// so with a placeholder and draws no meter, instead of the 100% the page used
// to hand it. Progress records its value so "no meter" is observable.
jest.mock('@/shared/components/ui/Progress', () => ({
  Progress: ({ value }: { value: unknown }) => <div data-testid="progress" data-value={String(value)} />,
}));

const provider = (performance: Partial<ProviderMetrics['performance']>): ProviderMetrics => ({
  id: 'p1',
  name: 'Provider One',
  slug: 'provider-one',
  status: 'healthy',
  health_score: 100,
  circuit_breaker: {
    state: 'closed',
    failure_count: 0,
    success_threshold: 5,
    timeout: 30000,
    last_failure: null,
    stats: { total_requests: 0, successful_requests: 0, failed_requests: 0, avg_response_time: 0 },
  },
  load_balancing: { current_load: 0, weight: 1, utilization: 0 },
  performance: { success_rate: null, avg_response_time: 12, throughput: 0, error_rate: null, ...performance },
  usage: { executions_count: 0, tokens_consumed: 0, cost: 0 },
  alerts: [],
  credentials: [],
  last_execution: null,
});

const renderGrid = (p: ProviderMetrics) =>
  renderWithProviders(<ProviderMonitoringGrid providers={[p]} isLoading={false} timeRange="24h" onRefresh={jest.fn()} />);
const row = (label: string) => screen.getByText(label).parentElement as HTMLElement;
const meterValues = () => screen.queryAllByTestId('progress').map((m) => m.getAttribute('data-value'));

describe('ProviderMonitoringGrid — success rate', () => {
  it('an unmeasured rate reads "—" and draws no meter', () => {
    renderGrid(provider({}));

    expect(within(row('Success Rate')).getByText('—')).toBeInTheDocument();
    expect(within(row('Success Rate')).queryByText(/%/)).not.toBeInTheDocument();
    expect(meterValues()).not.toContain('null');
  });

  it('a real 0% reads 0.0% with a meter at 0 — not a placeholder', () => {
    renderGrid(provider({ success_rate: 0, error_rate: 100 }));

    expect(within(row('Success Rate')).getByText('0.0%')).toBeInTheDocument();
    expect(meterValues()).toContain('0');
  });

  it('a measured rate reads through', () => {
    renderGrid(provider({ success_rate: 97.5, error_rate: 2.5 }));

    expect(within(row('Success Rate')).getByText('97.5%')).toBeInTheDocument();
    expect(meterValues()).toContain('97.5');
  });
});

import { screen, within } from '@testing-library/react';
import { renderWithProviders } from '@/test-utils';
import type { ProviderMetrics } from '@/shared/types/monitoring';
import { ProviderHealthCard } from './ProviderHealthCard';

// M1 tail: an unmeasured provider rate is a placeholder with no meter, never
// 100%, and an absent error rate draws no error row.
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

const renderCard = (p: ProviderMetrics) =>
  renderWithProviders(<ProviderHealthCard provider={p} isSelected={false} timeRange="24h" onSelect={jest.fn()} />);
const row = (label: string) => screen.getByText(label).parentElement as HTMLElement;
const meterValues = () => screen.queryAllByTestId('progress').map((m) => m.getAttribute('data-value'));

describe('ProviderHealthCard — rates', () => {
  it('an unmeasured provider reads "—", draws no meter and no error row', () => {
    renderCard(provider({}));

    expect(within(row('Success Rate')).getByText('—')).toBeInTheDocument();
    expect(meterValues()).not.toContain('null');
    expect(screen.queryByText('Error Rate')).not.toBeInTheDocument();
  });

  it('a provider failing every call reads 0.0% success and a 100.00% error row', () => {
    renderCard(provider({ success_rate: 0, error_rate: 100 }));

    expect(within(row('Success Rate')).getByText('0.0%')).toBeInTheDocument();
    expect(meterValues()).toContain('0');
    expect(within(row('Error Rate')).getByText('100.00%')).toBeInTheDocument();
  });
});

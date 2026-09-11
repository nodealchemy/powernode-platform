import { render, screen, within } from '@testing-library/react';
import type { ProviderMetrics } from '@/shared/types/monitoring';
import { LatencyPercentiles } from './LatencyPercentiles';

// M1 tail: the provider's rates may be absent. Absent reads "—", never a
// number standing in for "no data"; a real 0 still reads 0.
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

const tile = (label: string) => screen.getByText(label).parentElement as HTMLElement;

describe('LatencyPercentiles — rates', () => {
  it('absent rates read "—"', () => {
    render(<LatencyPercentiles provider={provider({})} />);

    expect(within(tile('Success Rate')).getByText('—')).toBeInTheDocument();
    expect(within(tile('Error Rate')).getByText('—')).toBeInTheDocument();
  });

  it('measured rates read through, a real 0 included', () => {
    render(<LatencyPercentiles provider={provider({ success_rate: 100, error_rate: 0 })} />);

    expect(within(tile('Success Rate')).getByText('100.00%')).toBeInTheDocument();
    expect(within(tile('Error Rate')).getByText('0.00%')).toBeInTheDocument();
  });
});

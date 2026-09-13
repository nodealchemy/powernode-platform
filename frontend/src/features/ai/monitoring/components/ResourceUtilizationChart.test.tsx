import { render, screen, within } from '@testing-library/react';
import type { ResourceUtilization } from '@/shared/types/monitoring';
import { ResourceUtilizationChart } from './ResourceUtilizationChart';

// M1 tail. The server reports the database pool's SIZE and nothing about its
// use or about storage. The page used to repeat the size as "used" and invent
// a 1000/100/900 storage split; now what was not measured reads "—".
jest.mock('@/shared/components/ui/Progress', () => ({
  Progress: ({ value }: { value: unknown }) => <div data-testid="progress" data-value={String(value)} />,
}));

const resources = (database: Partial<ResourceUtilization['database']>): ResourceUtilization => ({
  system: { cpu_usage: 10, memory_usage: 20, disk_usage: 0, network_usage: 0 },
  database: {
    connection_pool: { size: 10, used: null, available: null },
    query_performance: { avg_query_time: 0, slow_queries: 0, deadlocks: 0 },
    storage_usage: null,
    ...database,
  },
  redis: { memory_usage: { used: 0, peak: 0, limit: 0 }, connection_count: 0, hit_rate: 0 },
  sidekiq: { queue_sizes: {}, worker_utilization: { busy: 0, idle: 0, total: 0 }, failed_jobs: 0 },
  actioncable: { connection_count: 0, subscription_count: 0, message_throughput: 0 },
});

const renderChart = (data: ResourceUtilization) =>
  render(<ResourceUtilizationChart resourceData={data} isLoading={false} onRefresh={jest.fn()} />);
const section = (label: string) => screen.getByText(label).parentElement as HTMLElement;
// Meters inside ONE section: the Redis card draws its own, out of this scope.
const metersIn = (label: string) =>
  within(section(label)).queryAllByTestId('progress').map((m) => m.getAttribute('data-value'));

describe('ResourceUtilizationChart — database figures', () => {
  it('pool size only: "— / 10" with no pool meter, and storage reads "—" with no meter', () => {
    renderChart(resources({}));

    expect(within(section('Connection Pool')).getByText('— / 10')).toBeInTheDocument();
    expect(within(section('Storage')).getByText('—')).toBeInTheDocument();
    expect(metersIn('Connection Pool')).toEqual([]);
    expect(metersIn('Storage')).toEqual([]);
  });

  it('no pool size at all reads "— / —"', () => {
    renderChart(resources({ connection_pool: { size: null, used: null, available: null } }));

    expect(within(section('Connection Pool')).getByText('— / —')).toBeInTheDocument();
  });

  it('measured pool use and storage read through with their meters', () => {
    renderChart(resources({
      connection_pool: { size: 10, used: 4, available: 6 },
      storage_usage: { total_size: 1000, used_size: 250, free_size: 750 },
    }));

    expect(within(section('Connection Pool')).getByText('4 / 10')).toBeInTheDocument();
    expect(within(section('Storage')).getByText('25.0%')).toBeInTheDocument();
    expect(metersIn('Connection Pool')).toEqual(['40']);
    expect(metersIn('Storage')).toEqual(['25']);
  });
});

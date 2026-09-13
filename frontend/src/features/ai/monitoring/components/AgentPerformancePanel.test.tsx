import { screen } from '@testing-library/react';
import { renderWithProviders } from '@/test-utils';
import { AgentPerformancePanel } from '@/features/ai/monitoring/components/AgentPerformancePanel';
import type { AgentMetrics } from '@/shared/types/monitoring';

// M1 review F3. An agent with no measured rate renders as absent, never as a
// made-up 100%; an agent at a real 0% renders 0.0%, never 100%.

const agent = (name: string, rate: number | null): AgentMetrics => ({
  id: name,
  name,
  status: 'active',
  health_score: rate,
  performance: { success_rate: rate, avg_response_time: 0, throughput: 0, error_rate: rate === null ? null : 100 - rate },
  usage: { executions_count: 0, tokens_consumed: 0, cost: 0 },
  executions: { running: 0, completed: 0, failed: 0, cancelled: 0 },
  provider_distribution: [],
  alerts: [],
  last_execution: null,
  created_at: '2026-09-11T00:00:00Z',
  updated_at: '2026-09-11T00:00:00Z',
});

const renderPanel = (agents: AgentMetrics[]) =>
  // EntityLink reads permissions from the store, so the panel needs the
  // provider stack, not just a router.
  renderWithProviders(<AgentPerformancePanel agents={agents} isLoading={false} timeRange="1h" onRefresh={jest.fn()} />);

describe('AgentPerformancePanel — rates', () => {
  it('an agent with no measured rate shows a placeholder for health and success — never 100%', () => {
    renderPanel([agent('Never ran', null)]);

    expect(screen.getAllByText('—').length).toBeGreaterThanOrEqual(2);
    expect(screen.queryByText(/100\.0%/)).toBeNull();
    expect(screen.queryByText(/NaN|null/)).toBeNull();
  });

  it('an agent at a real 0% shows 0.0% for health and success', () => {
    renderPanel([agent('Always failed', 0)]);

    expect(screen.getAllByText('0.0%')).toHaveLength(2);
  });
});

import { render, screen } from '@testing-library/react';
import { SystemHealthDashboard } from './SystemHealthDashboard';
import type { HealthStatus } from '@/shared/services/ai/MonitoringApiService';

// E7b: the health service reports measurements only and stamps no verdict of
// its own. The overall verdict comes from the status-plane rollup the health
// action merges in beside the measurements. Before this fix, the component
// read `healthData.health_score.toFixed(1)` / `healthData.status`, which the
// backend no longer sends — a crash on the routed ObservabilityPage.
const basePayload: HealthStatus = {
  rollup: {
    verdict: 'degraded',
    held_count: 0,
    counts_by_verdict: { ok: 2, held: 0, progressing: 0, not_measured: 0, degraded: 1, down: 0 },
    total: 3,
  },
  shared: null,
  timestamp: new Date().toISOString(),
  system: { status: 'healthy', active_agents: 3, running_executions: 1 },
  database: { status: 'healthy' },
  redis: { status: 'healthy' },
  providers: { total_providers: 2, healthy_providers: 2, providers: [] },
  workers: { status: 'healthy', recent_completions: 5, recent_starts: 5, estimated_backlog: 0 },
};

describe('SystemHealthDashboard', () => {
  it('renders the rollup verdict without throwing on the post-E7b payload (no health_score/status)', () => {
    render(<SystemHealthDashboard healthData={basePayload} isLoading={false} onRefresh={jest.fn()} />);

    expect(screen.getByText('System Health')).toBeInTheDocument();
    expect(screen.getByRole('img', { name: /Overall status: Degraded/i })).toBeInTheDocument();
  });

  it('renders a "Not measured" fallback when the rollup is null rather than throwing', () => {
    render(
      <SystemHealthDashboard
        healthData={{ ...basePayload, rollup: null }}
        isLoading={false}
        onRefresh={jest.fn()}
      />
    );

    expect(screen.getByText('Not measured')).toBeInTheDocument();
  });
});

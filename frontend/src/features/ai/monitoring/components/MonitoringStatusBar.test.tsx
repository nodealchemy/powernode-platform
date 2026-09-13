import { render, screen } from '@testing-library/react';
import { MonitoringStatusBar } from './MonitoringStatusBar';
import type { HealthStatus } from '@/shared/services/ai/MonitoringApiService';

// E7b: `/ai/monitoring/health` no longer carries `health_score`/`status`.
// Before this fix the component read `systemHealth.health_score.toFixed(1)` /
// `systemHealth.status`, which throws on the post-E7b payload and blanks the
// routed ObservabilityPage.
const healthPayload: HealthStatus = {
  rollup: {
    verdict: 'down',
    held_count: 0,
    counts_by_verdict: { ok: 0, held: 0, progressing: 0, not_measured: 0, degraded: 0, down: 1 },
    total: 1,
  },
  shared: null,
  timestamp: new Date().toISOString(),
  system: { status: 'healthy', active_agents: 1, running_executions: 0 },
  database: { status: 'healthy' },
  redis: { status: 'healthy' },
  providers: { total_providers: 1, healthy_providers: 1, providers: [] },
  workers: { status: 'healthy', recent_completions: 0, recent_starts: 0, estimated_backlog: 0 },
};

describe('MonitoringStatusBar', () => {
  it('renders the rollup verdict without throwing on the post-E7b payload', () => {
    render(
      <MonitoringStatusBar
        isConnected
        systemHealth={healthPayload}
        lastUpdate={new Date()}
        timeRange="1h"
        onTimeRangeChange={jest.fn()}
      />
    );

    expect(screen.getByText('Connected')).toBeInTheDocument();
    expect(screen.getByRole('img', { name: /Down/i })).toBeInTheDocument();
  });

  it('renders a "Not measured" fallback when the rollup is null rather than throwing', () => {
    render(
      <MonitoringStatusBar
        isConnected
        systemHealth={{ ...healthPayload, rollup: null }}
        lastUpdate={new Date()}
        timeRange="1h"
        onTimeRangeChange={jest.fn()}
      />
    );

    expect(screen.getByText('Not measured')).toBeInTheDocument();
  });
});

import { render, screen } from '@testing-library/react';
import { DashboardAIOverview } from '@/features/ai/monitoring/components/DashboardAIOverview';
import type { DashboardStats } from '@/shared/hooks/useDashboardStats';
import type { Verdict } from '@/shared/types/platformStatus';

// M1 review F2 + F4. A not-measured platform must never read as healthy, never
// show a success badge, never print "null%"; and a FAILED read must never look
// like not_measured. Each example below is aimed at one of the reviewer's
// mutants (d1: badge not_measured -> ok; d2: score guard dropped).

const stats = (status: Verdict, score: number | null): DashboardStats => ({
  systemHealth: { status, score },
  overview: { totalExecutionsToday: 0, successRate: 0, avgResponseTime: 0, totalCostToday: 0 },
  agents: { total: 0, active: 0, paused: 0, errored: 0 },
  repositories: 0,
  alerts: [],
});

describe('DashboardAIOverview', () => {
  it('not measured: a "Not measured" badge, never OK, no health-score text, never "nominal", never "null"', () => {
    const { container } = render(<DashboardAIOverview stats={stats('not_measured', null)} loading={false} />);

    expect(screen.getByRole('img', { name: 'AI platform: Not measured' })).toBeInTheDocument();
    expect(screen.queryByRole('img', { name: 'AI platform: OK' })).toBeNull();
    expect(screen.queryByText(/health score/)).toBeNull();
    expect(screen.queryByText(/all systems nominal/i)).toBeNull();
    expect(container.textContent).not.toMatch(/null/);
  });

  it('ok: an OK badge and the real health score', () => {
    render(<DashboardAIOverview stats={stats('ok', 97)} loading={false} />);

    expect(screen.getByRole('img', { name: 'AI platform: OK' })).toBeInTheDocument();
    expect(screen.getByText('(97% health score)')).toBeInTheDocument();
  });

  it('a FAILED read is "Could not load" with the reason, and blanks the figures instead of zeroing them', () => {
    render(<DashboardAIOverview stats={stats('not_measured', null)} loading={false} monitoringError="Network Error" />);

    expect(screen.getByRole('alert')).toHaveTextContent('Could not load: Network Error');
    expect(screen.queryByRole('img', { name: /Not measured/ })).toBeNull();
    expect(screen.queryByText('0.0%')).toBeNull();
    expect(screen.queryByText('0ms')).toBeNull();
    expect(screen.getAllByText('—')).toHaveLength(4);
  });
});

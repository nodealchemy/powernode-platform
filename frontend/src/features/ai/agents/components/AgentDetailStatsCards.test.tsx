import { render, screen } from '@testing-library/react';
import { AgentDetailStatsCards } from './AgentDetailStatsCards';
import type { AgentStats } from '@/shared/services/ai/types/agent-api-types';

// IMP-e8513b30152d — useAgentDetail carries execution_stats.by_executor_kind
// (platform vs Claude Code) and its only consumer is AgentDetailModal, which
// hands `stats` to this component. Without a render here the hook's plumbing is
// inert: nothing displays the split the modal's data now contains.
const baseStats: AgentStats = {
  total_executions: 12,
  successful_executions: 10,
  failed_executions: 2,
  success_rate: 83,
  avg_execution_time: 1500,
  estimated_total_cost: '1.20',
  created_at: '2026-09-01T00:00:00Z',
};

describe('AgentDetailStatsCards', () => {
  it('renders the platform vs Claude Code split when by_executor_kind is present', () => {
    render(
      <AgentDetailStatsCards
        stats={{ ...baseStats, by_executor_kind: { platform: 9, claude_code: 3 } }}
      />
    );

    const split = screen.getByTestId('stats-by-executor-kind');
    expect(split).toHaveTextContent('9');
    expect(split).toHaveTextContent('3');
    expect(split).toHaveTextContent(/platform/i);
    expect(split).toHaveTextContent(/claude code/i);
    // The token-comparability convention rides the same element.
    expect(split.getAttribute('title')).toMatch(/cache_read/);
  });

  it('omits the split when the stats carry no by_executor_kind', () => {
    render(<AgentDetailStatsCards stats={baseStats} />);

    expect(screen.queryByTestId('stats-by-executor-kind')).toBeNull();
    expect(screen.getByText('12')).toBeInTheDocument();
  });
});

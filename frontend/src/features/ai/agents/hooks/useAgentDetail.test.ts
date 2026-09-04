import { renderHook, waitFor } from '@testing-library/react';
import { useAgentDetail } from './useAgentDetail';
import { agentsApi } from '@/shared/services/ai';

// IMP-e8513b30152d — by_executor_kind { platform, claude_code } rides the
// agent's embedded execution_stats (the show serializer); the stats endpoint
// (build_detailed_stats) does not carry it. The hook must surface it on
// `stats` whichever source won.
jest.mock('@/shared/services/ai', () => ({
  agentsApi: {
    getAgent: jest.fn(),
    getAgentStats: jest.fn(),
    getAgentAnalytics: jest.fn(),
  },
}));

const agent = {
  id: 'agent-1',
  name: 'CVE Responder',
  created_at: '2026-09-01T00:00:00Z',
  execution_stats: {
    total_executions: 5,
    successful_executions: 5,
    failed_executions: 0,
    success_rate: 100,
    avg_execution_time: 1.5,
    by_executor_kind: { platform: 3, claude_code: 2 },
  },
};

const endpointStats = {
  total_executions: 5,
  successful_executions: 5,
  failed_executions: 0,
  success_rate: 100,
  avg_execution_time: 1.5,
  estimated_total_cost: '0.42',
  created_at: '2026-09-01T00:00:00Z',
};

describe('useAgentDetail by_executor_kind', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    (agentsApi.getAgent as jest.Mock).mockResolvedValue(agent);
    (agentsApi.getAgentAnalytics as jest.Mock).mockRejectedValue(new Error('no analytics'));
  });

  it('carries by_executor_kind into the fallback stats when the stats endpoint fails', async () => {
    (agentsApi.getAgentStats as jest.Mock).mockRejectedValue(new Error('stats down'));

    const { result } = renderHook(() => useAgentDetail('agent-1'));

    await waitFor(() => expect(result.current.stats).not.toBeNull());
    expect(result.current.stats?.by_executor_kind).toEqual({ platform: 3, claude_code: 2 });
  });

  it('fills by_executor_kind from the embedded execution_stats when the stats endpoint succeeds without it', async () => {
    (agentsApi.getAgentStats as jest.Mock).mockResolvedValue(endpointStats);

    const { result } = renderHook(() => useAgentDetail('agent-1'));

    await waitFor(() => expect(result.current.stats).not.toBeNull());
    expect(result.current.stats?.estimated_total_cost).toBe('0.42');
    expect(result.current.stats?.by_executor_kind).toEqual({ platform: 3, claude_code: 2 });
  });

  it('keeps the stats endpoint value when it carries its own by_executor_kind', async () => {
    (agentsApi.getAgentStats as jest.Mock).mockResolvedValue({
      ...endpointStats,
      by_executor_kind: { platform: 4, claude_code: 1 },
    });

    const { result } = renderHook(() => useAgentDetail('agent-1'));

    await waitFor(() => expect(result.current.stats).not.toBeNull());
    expect(result.current.stats?.by_executor_kind).toEqual({ platform: 4, claude_code: 1 });
  });
});

import { useState, useEffect, useCallback } from 'react';
import { agentsApi } from '@/shared/services/ai';
import type { AiAgent } from '@/shared/types/ai';
import type { AgentStats, AgentAnalytics } from '@/shared/services/ai/types/agent-api-types';

interface UseAgentDetailResult {
  agent: AiAgent | null;
  stats: AgentStats | null;
  analytics: AgentAnalytics | null;
  loading: boolean;
  error: string | null;
  reload: () => void;
}

export function useAgentDetail(agentId: string | null): UseAgentDetailResult {
  const [agent, setAgent] = useState<AiAgent | null>(null);
  const [stats, setStats] = useState<AgentStats | null>(null);
  const [analytics, setAnalytics] = useState<AgentAnalytics | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!agentId) {
      setAgent(null);
      setStats(null);
      setAnalytics(null);
      setError(null);
      return;
    }

    try {
      setLoading(true);
      setError(null);

      const [agentData, statsData, analyticsData] = await Promise.allSettled([
        agentsApi.getAgent(agentId),
        agentsApi.getAgentStats(agentId),
        agentsApi.getAgentAnalytics(agentId, '30'),
      ]);

      if (agentData.status === 'fulfilled') {
        setAgent(agentData.value);
        // by_executor_kind (platform vs Claude Code runs) rides the agent's
        // embedded execution_stats; the stats endpoint does not carry it.
        const embedded = agentData.value.execution_stats;
        // Fall back to embedded execution_stats if stats endpoint fails
        if (statsData.status === 'fulfilled') {
          setStats({
            ...statsData.value,
            by_executor_kind: statsData.value.by_executor_kind ?? embedded?.by_executor_kind,
          });
        } else if (embedded) {
          setStats({
            total_executions: embedded.total_executions,
            successful_executions: embedded.successful_executions,
            failed_executions: embedded.failed_executions,
            success_rate: embedded.success_rate,
            avg_execution_time: embedded.avg_execution_time,
            estimated_total_cost: '0.00',
            created_at: agentData.value.created_at,
            by_executor_kind: embedded.by_executor_kind,
          });
        }
        if (analyticsData.status === 'fulfilled') {
          setAnalytics(analyticsData.value);
        } else {
          setAnalytics(null);
        }
      } else {
        setError(agentData.reason?.message || 'Failed to load agent');
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load agent');
    } finally {
      setLoading(false);
    }
  }, [agentId]);

  useEffect(() => {
    load();
  }, [load]);

  return { agent, stats, analytics, loading, error, reload: load };
}

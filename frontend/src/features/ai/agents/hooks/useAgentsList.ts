import { useState, useCallback, useMemo } from 'react';
import { useDispatch } from 'react-redux';
import { agentsApi } from '@/shared/services/ai';
import { addNotification } from '@/shared/services/slices/uiSlice';
import { getErrorMessage } from '@/shared/utils/apiErrors';
import type { AppDispatch } from '@/shared/services';
import type { AiAgent } from '@/shared/types/ai';

interface AgentOverviewStats {
  total_agents: number;
  active_agents: number;
  total_executions: number;
  success_rate: number;
}

export function useAgentsList() {
  const dispatch = useDispatch<AppDispatch>();

  const [agents, setAgents] = useState<AiAgent[]>([]);
  const [agentsLoading, setAgentsLoading] = useState(true);
  const [agentStats, setAgentStats] = useState<AgentOverviewStats>({
    total_agents: 0,
    active_agents: 0,
    total_executions: 0,
    success_rate: 0,
  });
  const [agentSearchQuery, setAgentSearchQuery] = useState('');
  const [agentViewMode, setAgentViewMode] = useState<'grid' | 'list'>('grid');

  const loadAgents = useCallback(async () => {
    try {
      setAgentsLoading(true);
      const { items: agentsData } = await agentsApi.getAgents({ per_page: 50 });

      if (!agentsData || !Array.isArray(agentsData) || agentsData.length === 0) {
        setAgents([]);
        setAgentStats({ total_agents: 0, active_agents: 0, total_executions: 0, success_rate: 0 });
        return;
      }

      setAgents(agentsData as AiAgent[]);

      const activeAgents = agentsData.filter((a: AiAgent) => a.status === 'active').length;
      const totalExecutions = agentsData.reduce((sum: number, agent: AiAgent) =>
        sum + (agent.execution_stats?.total_executions || 0), 0
      );
      const avgSuccessRate = agentsData.length > 0 ?
        agentsData.reduce((sum: number, agent: AiAgent) =>
          sum + (agent.execution_stats?.success_rate || 0), 0
        ) / agentsData.length : 0;

      setAgentStats({
        total_agents: agentsData.length,
        active_agents: activeAgents,
        total_executions: totalExecutions,
        success_rate: Math.round(avgSuccessRate),
      });
    } catch (error) {
      setAgents([]);
      setAgentStats({ total_agents: 0, active_agents: 0, total_executions: 0, success_rate: 0 });
      dispatch(addNotification({
        type: 'error',
        message: getErrorMessage(error, 'Failed to load agents'),
      }));
    } finally {
      setAgentsLoading(false);
    }
  }, [dispatch]);

  const handleToggleAgentStatus = useCallback(async (agent: AiAgent) => {
    try {
      if (agent.status === 'active') {
        await agentsApi.pauseAgent(agent.id);
        dispatch(addNotification({ type: 'success', message: `${agent.name} has been paused` }));
      } else {
        await agentsApi.resumeAgent(agent.id);
        dispatch(addNotification({ type: 'success', message: `${agent.name} has been resumed` }));
      }
      loadAgents();
    } catch (_error) {
      dispatch(addNotification({ type: 'error', message: 'Failed to update agent status' }));
    }
  }, [dispatch, loadAgents]);

  const filteredAgents = useMemo(() => {
    if (!agentSearchQuery) return agents;
    const q = agentSearchQuery.toLowerCase();
    return agents.filter(a =>
      a.name.toLowerCase().includes(q) ||
      a.description?.toLowerCase().includes(q) ||
      a.provider?.name?.toLowerCase().includes(q) ||
      a.model?.toLowerCase().includes(q)
    );
  }, [agents, agentSearchQuery]);

  return {
    agents,
    agentsLoading,
    agentStats,
    agentSearchQuery,
    setAgentSearchQuery,
    agentViewMode,
    setAgentViewMode,
    loadAgents,
    handleToggleAgentStatus,
    filteredAgents,
  };
}

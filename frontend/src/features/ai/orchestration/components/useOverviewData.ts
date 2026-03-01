import { useState, useEffect, useCallback } from 'react';
import { agentsApi, providersApi, conversationsApi } from '@/shared/services/ai';
import { workflowsApi } from '@/shared/services/ai';
import { useAIOrchestrationMonitor, resetAIOrchestrationMonitor } from '../services/aiOrchestrationMonitor';
import type { AISystemMetrics } from '../services/aiOrchestrationMonitor';

export interface OverviewStats {
  providers: {
    total: number;
    active: number;
    health_status: 'healthy' | 'degraded' | 'critical';
  };
  agents: {
    total: number;
    active: number;
    executing: number;
    success_rate: number;
  };
  workflows: {
    total: number;
    active: number;
    executing: number;
    success_rate: number;
  };
  conversations: {
    total: number;
    active: number;
    today: number;
  };
  executions: {
    total_month: number;
    total_today: number;
    success_rate: number;
    avg_response_time: number;
  };
}

interface ProviderItem {
  id: string;
  name: string;
  is_active: boolean;
  health_status: 'healthy' | 'degraded' | 'critical' | 'unknown';
}

interface AgentItem {
  id: string;
  name: string;
  status: 'active' | 'inactive' | 'error';
  type?: string;
  success_rate?: number;
  execution_count?: number;
}

interface WorkflowItem {
  id: string;
  name: string;
  status: 'draft' | 'published' | 'archived' | 'active';
  last_run?: string;
}

interface ConversationItem {
  id: string;
  title: string | null;
  status: 'active' | 'paused' | 'completed' | 'archived';
  created_at: string;
  message_count: number;
}

interface ApiListResponse<T> {
  items?: T[];
  providers?: T[];
  agents?: T[];
  workflows?: T[];
  data?: {
    items?: T[];
    providers?: T[];
    agents?: T[];
    workflows?: T[];
  };
}

function extractItems<T>(response: ApiListResponse<T>, key: 'providers' | 'agents' | 'workflows'): T[] {
  if (response?.items) return response.items;
  if (response?.[key]) return response[key] as T[];
  if (response?.data?.items) return response.data.items;
  if (response?.data?.[key]) return response.data[key] as T[];
  return [];
}

export function useOverviewData() {
  const { subscribe, isConnected } = useAIOrchestrationMonitor();

  const [stats, setStats] = useState<OverviewStats | null>(null);
  const [loading, setLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [isLiveUpdateActive, setIsLiveUpdateActive] = useState(false);
  const [recentUpdates, setRecentUpdates] = useState<string[]>([]);
  const [, setHasConnectionAttempted] = useState(false);

  // Real-time metrics updates
  useEffect(() => {
    const unsubscribe = subscribe(
      undefined,
      (metrics: AISystemMetrics) => {
        const updatedSections: string[] = [];

        setStats(prevStats => {
          if (!prevStats) {
            return {
              ...metrics,
              conversations: { total: 0, active: 0, today: 0 },
              executions: {
                ...metrics.executions,
                total_month: 0,
              },
            };
          }

          if (JSON.stringify(metrics.providers) !== JSON.stringify(prevStats.providers)) updatedSections.push('providers');
          if (JSON.stringify(metrics.agents) !== JSON.stringify(prevStats.agents)) updatedSections.push('agents');
          if (JSON.stringify(metrics.workflows) !== JSON.stringify(prevStats.workflows)) updatedSections.push('workflows');
          if (JSON.stringify(metrics.executions) !== JSON.stringify(prevStats.executions)) updatedSections.push('executions');

          return {
            ...prevStats,
            ...metrics,
            conversations: prevStats.conversations,
            executions: {
              ...metrics.executions,
              total_month: prevStats.executions.total_month,
            },
          };
        });

        if (updatedSections.length > 0) {
          setRecentUpdates(updatedSections);
          setTimeout(() => setRecentUpdates([]), 3000);
        }
      }
    );
    return unsubscribe;
  }, []);

  // Track connection attempt after initial delay
  useEffect(() => {
    const timeoutId = setTimeout(() => {
      setHasConnectionAttempted(true);
    }, 2000);
    return () => clearTimeout(timeoutId);
  }, []);

  const loadOverviewData = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);

      const [providersRes, agentsRes, workflowsRes] = await Promise.allSettled([
        providersApi.getProviders({ per_page: 100 }),
        agentsApi.getAgents({ per_page: 100 }),
        workflowsApi.getWorkflows({ perPage: 100 }),
      ]);

      // Process providers
      let providers: ProviderItem[] = [];
      if (providersRes.status === 'fulfilled') {
        providers = extractItems(providersRes.value as ApiListResponse<ProviderItem>, 'providers');
      }
      const activeProviders = providers.filter((p) => p.is_active);
      const healthyProviders = providers.filter((p) => p.health_status === 'healthy');
      let providerHealthStatus: 'healthy' | 'degraded' | 'critical' = 'healthy';
      if (healthyProviders.length === 0) providerHealthStatus = 'critical';
      else if (healthyProviders.length < providers.length * 0.8) providerHealthStatus = 'degraded';

      // Process agents
      let agents: AgentItem[] = [];
      if (agentsRes.status === 'fulfilled') {
        agents = extractItems(agentsRes.value as ApiListResponse<AgentItem>, 'agents');
      }
      const activeAgents = agents.filter((a) => a.status === 'active');
      const agentSuccessRate = agents.length > 0
        ? agents.reduce((acc, agent) => acc + (agent.success_rate || 95), 0) / agents.length
        : 0;

      // Process workflows
      let workflows: WorkflowItem[] = [];
      if (workflowsRes.status === 'fulfilled') {
        workflows = extractItems(workflowsRes.value as ApiListResponse<WorkflowItem>, 'workflows');
      }
      const activeWorkflows = workflows.filter((w) => w.status === 'active' || w.status === 'published');

      // Fetch real conversations
      let conversations: ConversationItem[] = [];
      try {
        const convRes = await conversationsApi.getConversations({ per_page: 100 });
        conversations = (convRes?.items || []) as ConversationItem[];
      } catch {
        // Conversations API unavailable — use empty array
      }
      const activeConversations = conversations.filter((c) => c.status === 'active');
      const todayConversations = conversations.filter((c) => new Date(c.created_at).toDateString() === new Date().toDateString());

      const totalExecutionsMonth = agents.reduce((acc, agent) => acc + (agent.execution_count || 0), 0);
      const workflowSuccessRate = workflows.length > 0 ? agentSuccessRate : 0;
      const overallSuccessRate = agents.length > 0 ? (agentSuccessRate + workflowSuccessRate) / (workflows.length > 0 ? 2 : 1) : 0;

      setStats({
        providers: { total: providers.length, active: activeProviders.length, health_status: providerHealthStatus },
        agents: { total: agents.length, active: activeAgents.length, executing: 0, success_rate: Math.round(agentSuccessRate) },
        workflows: { total: workflows.length, active: activeWorkflows.length, executing: 0, success_rate: Math.round(workflowSuccessRate) },
        conversations: { total: conversations.length, active: activeConversations.length, today: todayConversations.length },
        executions: { total_month: totalExecutionsMonth, total_today: 0, success_rate: Math.round(overallSuccessRate), avg_response_time: 0 },
      });
    } catch (err) {
      let errorMessage = 'Failed to load AI system data';
      if (err instanceof Error) {
        errorMessage = err.message;
      } else if (typeof err === 'object' && err !== null && 'response' in err) {
        const responseErr = err as { response?: { status?: number } };
        const status = responseErr.response?.status;
        if (status === 401) errorMessage = 'Authentication required - please log in';
        else if (status === 403) errorMessage = 'Access denied - insufficient permissions';
        else if (status && status >= 500) errorMessage = 'Server error - please try again later';
        else errorMessage = `API error: ${status || 'Unknown'}`;
      }
      setError(errorMessage);
    } finally {
      setLoading(false);
    }
  }, []);

  // Initial load
  useEffect(() => {
    resetAIOrchestrationMonitor();
    loadOverviewData();
  }, []);

  // Fallback polling when WebSocket is down
  useEffect(() => {
    if (!isLiveUpdateActive || isConnected()) return;
    const updateInterval = setInterval(() => { loadOverviewData(); }, 30000);
    return () => clearInterval(updateInterval);
  }, [isLiveUpdateActive, isConnected, loadOverviewData]);

  const handleRefresh = useCallback(async () => {
    setIsRefreshing(true);
    await loadOverviewData();
    setIsRefreshing(false);
  }, [loadOverviewData]);

  const toggleLiveUpdates = useCallback(() => {
    setIsLiveUpdateActive(prev => !prev);
  }, []);

  return {
    stats, loading, error, isRefreshing, isLiveUpdateActive, recentUpdates,
    loadOverviewData, handleRefresh, toggleLiveUpdates,
  };
}

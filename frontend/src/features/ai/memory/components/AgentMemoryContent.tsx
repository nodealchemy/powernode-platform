import React, { useState, useEffect, useCallback } from 'react';
import { Brain } from 'lucide-react';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useRefreshAction } from '@/shared/hooks/useRefreshAction';
import { agentsApi } from '@/shared/services/ai';
import { MemoryStats } from './AgentMemoryStats';
import { MemoryTimeline } from './MemoryTimeline';
import { SharedLearningsPanel } from './SharedLearningsPanel';
import type { PageAction } from '@/shared/components/layout/PageContainer';
import type { AiAgent } from '@/shared/types/ai';

interface AgentMemoryContentProps {
  onActionsReady?: (actions: PageAction[]) => void;
}

export const AgentMemoryContent: React.FC<AgentMemoryContentProps> = ({ onActionsReady }) => {
  const { addNotification } = useNotifications();
  const [agents, setAgents] = useState<AiAgent[]>([]);
  const [agentsLoading, setAgentsLoading] = useState(true);
  const [selectedAgentId, setSelectedAgentId] = useState('');
  const [refreshKey, setRefreshKey] = useState(0);

  useEffect(() => {
    const loadAgents = async () => {
      try {
        setAgentsLoading(true);
        const { items } = await agentsApi.getAgents({ per_page: 100 });
        const agentsList = (items || []) as AiAgent[];
        setAgents(agentsList);
        if (agentsList.length > 0 && !selectedAgentId) {
          setSelectedAgentId(agentsList[0].id);
        }
      } catch (_error) {
        addNotification({ type: 'error', message: 'Failed to load agents' });
      } finally {
        setAgentsLoading(false);
      }
    };
    loadAgents();
  }, []);

  const handleRefresh = useCallback(() => {
    setRefreshKey((k) => k + 1);
  }, []);

  const { refreshAction } = useRefreshAction({ onRefresh: handleRefresh });

  useEffect(() => {
    if (onActionsReady) {
      onActionsReady([refreshAction]);
    }
  }, [onActionsReady, refreshAction]);

  if (agentsLoading) {
    return <LoadingSpinner size="lg" className="py-12" message="Loading agents..." />;
  }

  return (
    <div className="space-y-6">
      {/* Agent Selector */}
      <Card>
        <CardContent className="p-4">
          <div className="flex items-center gap-3">
            <Brain className="h-5 w-5 text-theme-primary shrink-0" />
            <label className="text-sm font-medium text-theme-secondary shrink-0">Agent:</label>
            <select
              value={selectedAgentId}
              onChange={(e) => setSelectedAgentId(e.target.value)}
              className="flex-1 text-sm rounded-lg bg-theme-surface border border-theme-border text-theme-primary py-2 px-3 focus:outline-none focus:ring-2 focus:ring-theme-primary"
            >
              {agents.length === 0 && <option value="">No agents available</option>}
              {agents.map((agent) => (
                <option key={agent.id} value={agent.id}>
                  {agent.name} ({agent.status})
                </option>
              ))}
            </select>
          </div>
        </CardContent>
      </Card>

      {selectedAgentId && (
        <>
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
            <div className="lg:col-span-2">
              <MemoryTimeline key={`timeline-${refreshKey}`} agentId={selectedAgentId} />
            </div>
            <div className="space-y-6">
              <MemoryStats key={`stats-${refreshKey}`} agentId={selectedAgentId} />
              <SharedLearningsPanel />
            </div>
          </div>
        </>
      )}
    </div>
  );
};

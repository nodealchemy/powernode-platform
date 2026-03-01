import React from 'react';
import { BarChart3 } from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';
import type { AiAgent } from '@/shared/types/ai';
import type { AgentStats } from '@/shared/services/ai/types/agent-api-types';

interface AgentStatsSectionProps {
  agent: AiAgent;
  agentStats: AgentStats;
}

export const AgentStatsSection: React.FC<AgentStatsSectionProps> = ({ agent, agentStats }) => {
  const getAgentStatusBadge = () => {
    switch (agent.status) {
      case 'active':
        return <Badge variant="success" size="sm">Active</Badge>;
      case 'inactive':
        return <Badge variant="secondary" size="sm">Inactive</Badge>;
      case 'error':
        return <Badge variant="danger" size="sm">Error</Badge>;
      default:
        return <Badge variant="outline" size="sm">Unknown</Badge>;
    }
  };

  return (
    <div className="bg-theme-surface border border-theme rounded-lg p-4">
      <div className="flex items-center gap-3 mb-4">
        <div className="h-10 w-10 bg-theme-info bg-opacity-10 rounded-lg flex items-center justify-center">
          <BarChart3 className="h-5 w-5 text-theme-info" />
        </div>
        <div>
          <h5 className="font-semibold text-theme-primary">Performance Stats</h5>
          <div className="flex items-center gap-2 mt-1">
            {getAgentStatusBadge()}
            <span className="text-sm text-theme-secondary">
              Created {new Date(agent.created_at).toLocaleDateString()}
            </span>
          </div>
        </div>
      </div>

      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <div className="text-center">
          <div className="text-lg font-semibold text-theme-primary">{agentStats.total_executions || 0}</div>
          <div className="text-xs text-theme-tertiary">Total Executions</div>
        </div>
        <div className="text-center">
          <div className="text-lg font-semibold text-theme-success">{agentStats.success_rate || 0}%</div>
          <div className="text-xs text-theme-tertiary">Success Rate</div>
        </div>
        <div className="text-center">
          <div className="text-lg font-semibold text-theme-primary">{agentStats.avg_execution_time || 0}ms</div>
          <div className="text-xs text-theme-tertiary">Avg Time</div>
        </div>
        <div className="text-center">
          <div className="text-lg font-semibold text-theme-warning">${agentStats.estimated_total_cost || '0.00'}</div>
          <div className="text-xs text-theme-tertiary">Total Cost</div>
        </div>
      </div>
    </div>
  );
};

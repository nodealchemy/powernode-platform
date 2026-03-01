import React from 'react';
import { useNavigate } from 'react-router-dom';
import { Settings, Bot, Workflow, Zap, ArrowRight } from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';
import { Progress } from '@/shared/components/ui/Progress';
import type { OverviewStats } from './useOverviewData';

interface OverviewStatsGridProps {
  stats: OverviewStats | null;
  recentUpdates: string[];
}

const getHealthBadge = (status: string) => {
  switch (status) {
    case 'healthy': return <Badge variant="success" size="sm">Healthy</Badge>;
    case 'degraded': return <Badge variant="warning" size="sm">Degraded</Badge>;
    case 'critical': return <Badge variant="danger" size="sm">Critical</Badge>;
    default: return <Badge variant="secondary" size="sm">Unknown</Badge>;
  }
};

export const OverviewStatsGrid: React.FC<OverviewStatsGridProps> = ({ stats, recentUpdates }) => {
  const navigate = useNavigate();

  return (
    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
      {/* AI Providers Card */}
      <div className={`card-theme p-6 hover:shadow-lg transition-all cursor-pointer ${
        recentUpdates.includes('providers') ? 'ring-2 ring-theme-success ring-opacity-50 bg-theme-success/5' : ''
      }`} onClick={() => navigate('/app/ai/providers')}>
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-theme-primary/10 rounded-lg">
              <Settings className="h-5 w-5 text-theme-primary" />
            </div>
            <div>
              <div className="text-2xl font-bold text-theme-primary">{stats?.providers.total || 0}</div>
              <div className="text-sm text-theme-secondary">AI Providers</div>
            </div>
          </div>
          <ArrowRight className="h-4 w-4 text-theme-muted" />
        </div>
        <div className="space-y-2">
          <div className="flex items-center justify-between text-sm">
            <span className="text-theme-secondary">Active</span>
            <span className="font-medium">{stats?.providers.active || 0}</span>
          </div>
          <div className="flex items-center justify-between text-sm">
            <span className="text-theme-secondary">Health</span>
            {stats && getHealthBadge(stats.providers.health_status)}
          </div>
        </div>
      </div>

      {/* AI Agents Card */}
      <div className={`card-theme p-6 hover:shadow-lg transition-all cursor-pointer ${
        recentUpdates.includes('agents') ? 'ring-2 ring-theme-success ring-opacity-50 bg-theme-success/5' : ''
      }`} onClick={() => navigate('/app/ai/agents')}>
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-theme-info/10 rounded-lg">
              <Bot className="h-5 w-5 text-theme-info" />
            </div>
            <div>
              <div className="text-2xl font-bold text-theme-primary">{stats?.agents.total || 0}</div>
              <div className="text-sm text-theme-secondary">AI Agents</div>
            </div>
          </div>
          <ArrowRight className="h-4 w-4 text-theme-muted" />
        </div>
        <div className="space-y-2">
          <div className="flex items-center justify-between text-sm">
            <span className="text-theme-secondary">Active</span>
            <span className="font-medium">{stats?.agents.active || 0}</span>
          </div>
          <div className="flex items-center justify-between text-sm">
            <span className="text-theme-secondary">Success Rate</span>
            <span className="font-medium">{stats?.agents.success_rate || 0}%</span>
          </div>
          <Progress value={stats?.agents.success_rate || 0} className="h-1" />
        </div>
      </div>

      {/* Workflows Card */}
      <div className={`card-theme p-6 hover:shadow-lg transition-all cursor-pointer ${
        recentUpdates.includes('workflows') ? 'ring-2 ring-theme-success ring-opacity-50 bg-theme-success/5' : ''
      }`} onClick={() => navigate('/app/ai/workflows')}>
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-theme-warning/10 rounded-lg">
              <Workflow className="h-5 w-5 text-theme-warning" />
            </div>
            <div>
              <div className="text-2xl font-bold text-theme-primary">{stats?.workflows.total || 0}</div>
              <div className="text-sm text-theme-secondary">Workflows</div>
            </div>
          </div>
          <ArrowRight className="h-4 w-4 text-theme-muted" />
        </div>
        <div className="space-y-2">
          <div className="flex items-center justify-between text-sm">
            <span className="text-theme-secondary">Executing</span>
            <span className="font-medium">{stats?.workflows.executing || 0}</span>
          </div>
          <div className="flex items-center justify-between text-sm">
            <span className="text-theme-secondary">Success Rate</span>
            <span className="font-medium">{stats?.workflows.success_rate || 0}%</span>
          </div>
          <Progress value={stats?.workflows.success_rate || 0} className="h-1" />
        </div>
      </div>

      {/* Executions Card */}
      <div className={`card-theme p-6 hover:shadow-lg transition-all cursor-pointer ${
        recentUpdates.includes('executions') ? 'ring-2 ring-theme-success ring-opacity-50 bg-theme-success/5' : ''
      }`} onClick={() => navigate('/app/ai/analytics')}>
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-theme-success/10 rounded-lg">
              <Zap className="h-5 w-5 text-theme-success" />
            </div>
            <div>
              <div className="text-2xl font-bold text-theme-primary">{stats?.executions.total_month || 0}</div>
              <div className="text-sm text-theme-secondary">Executions</div>
            </div>
          </div>
          <ArrowRight className="h-4 w-4 text-theme-muted" />
        </div>
        <div className="space-y-2">
          <div className="flex items-center justify-between text-sm">
            <span className="text-theme-secondary">Today</span>
            <span className="font-medium">{stats?.executions.total_today || 0}</span>
          </div>
          <div className="flex items-center justify-between text-sm">
            <span className="text-theme-secondary">Avg Response</span>
            <span className="font-medium">{stats?.executions.avg_response_time || 0}ms</span>
          </div>
        </div>
      </div>
    </div>
  );
};

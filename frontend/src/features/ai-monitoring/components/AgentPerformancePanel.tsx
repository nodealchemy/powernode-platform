import React from 'react';
import {
  Bot,
  Clock,
  RefreshCw,
  TestTube
} from 'lucide-react';
import { Card, CardHeader, CardContent } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { Progress } from '@/shared/components/ui/Progress';
import { Loading } from '@/shared/components/ui/Loading';
import { AgentMetrics } from '@/shared/types/monitoring';

interface AgentPerformancePanelProps {
  agents: AgentMetrics[];
  isLoading: boolean;
  timeRange: string;
  onRefresh: () => void;
  onTestAgent?: (agentId: string, params: any) => void;
}

export const AgentPerformancePanel: React.FC<AgentPerformancePanelProps> = ({
  agents,
  isLoading,
  timeRange: _timeRange,
  onRefresh,
  onTestAgent
}) => {
  const getStatusBadge = (status: string) => {
    switch (status) {
      case 'active': return 'success';
      case 'inactive': return 'outline';
      case 'error': return 'danger';
      default: return 'outline';
    }
  };

  if (isLoading && agents.length === 0) {
    return (
      <Card>
        <CardHeader title="Agent Performance" />
        <CardContent className="flex items-center justify-center py-8">
          <Loading size="lg" message="Loading agent data..." />
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h3 className="text-lg font-medium text-theme-primary">AI Agent Performance</h3>
        <Button
          onClick={onRefresh}
          variant="outline"
          size="sm"
          disabled={isLoading}
        >
          <RefreshCw className={`h-4 w-4 mr-2 ${isLoading ? 'animate-spin' : ''}`} />
          Refresh
        </Button>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
        {agents.map((agent) => (
          <Card key={agent.id} className="relative">
            <CardHeader
              title={agent.name}
              icon={<Bot className="h-5 w-5" />}
              action={<Badge variant={getStatusBadge(agent.status)}>{agent.status}</Badge>}
              className="pb-3"
            />
            <CardContent className="space-y-4">
              {/* Health Score */}
              <div className="flex items-center justify-between">
                <span className="text-sm text-theme-muted">Health Score</span>
                <span className={`font-medium ${agent.health_score >= 90 ? 'text-theme-success' : agent.health_score >= 70 ? 'text-theme-warning' : 'text-theme-error'}`}>
                  {agent.health_score.toFixed(1)}%
                </span>
              </div>

              {/* Performance Metrics */}
              <div className="space-y-2">
                <div className="flex items-center justify-between text-sm">
                  <span className="text-theme-muted">Success Rate</span>
                  <span className={agent.performance.success_rate >= 95 ? 'text-theme-success' : agent.performance.success_rate >= 90 ? 'text-theme-warning' : 'text-theme-error'}>
                    {agent.performance.success_rate.toFixed(1)}%
                  </span>
                </div>
                <Progress value={agent.performance.success_rate} className="h-2" />
              </div>

              {/* Execution Stats */}
              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-1">
                  <div className="flex items-center justify-between text-sm">
                    <span className="text-theme-muted">Running</span>
                    <span className="font-medium text-theme-info">
                      {agent.executions.running}
                    </span>
                  </div>
                  <div className="flex items-center justify-between text-sm">
                    <span className="text-theme-muted">Completed</span>
                    <span className="font-medium text-theme-success">
                      {agent.executions.completed}
                    </span>
                  </div>
                </div>
                <div className="space-y-1">
                  <div className="flex items-center justify-between text-sm">
                    <span className="text-theme-muted">Failed</span>
                    <span className="font-medium text-theme-error">
                      {agent.executions.failed}
                    </span>
                  </div>
                  <div className="flex items-center justify-between text-sm">
                    <span className="text-theme-muted">Cancelled</span>
                    <span className="font-medium text-theme-muted">
                      {agent.executions.cancelled}
                    </span>
                  </div>
                </div>
              </div>

              {/* Usage Stats */}
              <div className="grid grid-cols-2 gap-4 text-sm">
                <div>
                  <span className="text-theme-muted block">Tokens Used</span>
                  <span className="font-medium">
                    {agent.usage.tokens_consumed.toLocaleString()}
                  </span>
                </div>
                <div>
                  <span className="text-theme-muted block">Total Cost</span>
                  <span className="font-medium">
                    ${agent.usage.cost.toFixed(4)}
                  </span>
                </div>
              </div>

              {/* Response Time */}
              <div className="flex items-center justify-between text-sm">
                <span className="text-theme-muted">Avg Response</span>
                <span className="font-medium">
                  {agent.performance.avg_response_time.toFixed(0)}ms
                </span>
              </div>

              {/* Provider Distribution */}
              {agent.provider_distribution.length > 0 && (
                <div className="space-y-2">
                  <span className="text-sm text-theme-muted">Provider Usage</span>
                  <div className="space-y-1">
                    {agent.provider_distribution.slice(0, 2).map((provider, index) => (
                      <div key={index} className="flex items-center justify-between text-xs">
                        <span className="text-theme-muted">{provider.provider_name}</span>
                        <span className="font-medium">{provider.execution_count}</span>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {/* Last Execution */}
              {agent.last_execution && (
                <div className="flex items-center gap-2 text-xs text-theme-muted">
                  <Clock className="h-3 w-3" />
                  <span>Last: {new Date(agent.last_execution).toLocaleTimeString()}</span>
                </div>
              )}

              {/* Actions */}
              {onTestAgent && (
                <div className="pt-2 border-t border-theme-border">
                  <Button
                    onClick={() => onTestAgent(agent.id, {})}
                    variant="outline"
                    size="sm"
                    className="w-full"
                    disabled={agent.status !== 'active'}
                  >
                    <TestTube className="h-4 w-4 mr-2" />
                    Test Agent
                  </Button>
                </div>
              )}
            </CardContent>
          </Card>
        ))}
      </div>

      {agents.length === 0 && !isLoading && (
        <Card>
          <CardContent className="py-8 text-center">
            <Bot className="h-12 w-12 text-theme-muted mx-auto mb-4" />
            <p className="text-theme-muted">No agents found</p>
          </CardContent>
        </Card>
      )}
    </div>
  );
};
import React from 'react';
import { Card } from '@/shared/components/ui/Card';

interface ProviderMetric {
  id: string;
  name: string;
  health_status: string;
  success_rate: number;
  avg_response_time: number;
  total_requests: number;
  cost_today: number;
}

interface TopAgent {
  id: string;
  name: string;
  executions: number;
  success_rate: number;
  total_cost: number;
}

interface ProviderMetricsListProps {
  providerMetrics: ProviderMetric[];
  topAgents: TopAgent[];
}

export const ProviderMetricsList: React.FC<ProviderMetricsListProps> = ({
  providerMetrics,
  topAgents,
}) => {
  return (
    <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
      {/* Provider Performance */}
      <Card className="p-6">
        <h3 className="text-lg font-semibold text-theme-primary mb-4">
          Provider Performance
        </h3>
        <div className="space-y-4">
          {providerMetrics.map((provider) => (
            <div key={provider.id} className="flex items-center justify-between p-3 bg-theme-surface rounded-lg">
              <div className="flex items-center gap-3">
                <div className={`w-3 h-3 rounded-full ${
                  provider.health_status === 'healthy' ? 'bg-theme-success' : 'bg-theme-error'
                }`} />
                <div>
                  <p className="font-medium text-theme-primary">{provider.name}</p>
                  <p className="text-sm text-theme-tertiary">
                    {provider.total_requests} requests • {provider.avg_response_time}ms avg
                  </p>
                </div>
              </div>

              <div className="text-right">
                <p className="font-semibold text-theme-primary">
                  {provider.success_rate.toFixed(1)}%
                </p>
                <p className="text-sm text-theme-tertiary">
                  ${provider.cost_today.toFixed(2)}
                </p>
              </div>
            </div>
          ))}
        </div>
      </Card>

      {/* Top Performing Agents */}
      <Card className="p-6">
        <h3 className="text-lg font-semibold text-theme-primary mb-4">
          Top Performing Agents
        </h3>
        <div className="space-y-4">
          {topAgents.map((agent, index) => (
            <div key={agent.id} className="flex items-center justify-between p-3 bg-theme-surface rounded-lg">
              <div className="flex items-center gap-3">
                <div className="w-8 h-8 bg-theme-info rounded-full flex items-center justify-center text-white text-sm font-semibold">
                  {index + 1}
                </div>
                <div>
                  <p className="font-medium text-theme-primary">{agent.name}</p>
                  <p className="text-sm text-theme-tertiary">
                    {agent.executions} executions
                  </p>
                </div>
              </div>

              <div className="text-right">
                <p className="font-semibold text-theme-primary">
                  {agent.success_rate.toFixed(1)}%
                </p>
                <p className="text-sm text-theme-tertiary">
                  ${agent.total_cost.toFixed(2)}
                </p>
              </div>
            </div>
          ))}
        </div>
      </Card>
    </div>
  );
};

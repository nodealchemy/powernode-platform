import React from 'react';
import { Zap } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { CostAnalytics } from '@/shared/services/ai';

interface CostMetricsPanelProps {
  costAnalytics: CostAnalytics;
}

export const CostMetricsPanel: React.FC<CostMetricsPanelProps> = ({ costAnalytics }) => {
  return (
    <div className="mt-6">
      <Card className="p-6">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-lg font-semibold text-theme-primary">
            Cost Analytics
          </h3>
          {costAnalytics.optimization_potential_usd > 0 && (
            <Badge variant="success" size="sm">
              <Zap className="h-3 w-3 mr-1" />
              ${costAnalytics.optimization_potential_usd.toFixed(2)} savings potential
            </Badge>
          )}
        </div>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
          <div className="p-4 bg-theme-surface rounded-lg">
            <p className="text-sm text-theme-tertiary">Total Cost</p>
            <p className="text-2xl font-semibold text-theme-primary">
              ${costAnalytics.total_cost_usd.toFixed(2)}
            </p>
          </div>

          <div className="p-4 bg-theme-surface rounded-lg">
            <p className="text-sm text-theme-tertiary">Cost by Provider</p>
            <div className="mt-2 space-y-1">
              {Object.entries(costAnalytics.cost_by_provider).slice(0, 3).map(([provider, cost]) => (
                <div key={provider} className="flex justify-between text-sm">
                  <span className="text-theme-secondary">{provider}</span>
                  <span className="font-medium text-theme-primary">${(cost as number).toFixed(2)}</span>
                </div>
              ))}
            </div>
          </div>

          <div className="p-4 bg-theme-surface rounded-lg">
            <p className="text-sm text-theme-tertiary">Top Expensive Workflows</p>
            <div className="mt-2 space-y-1">
              {costAnalytics.top_expensive_workflows.slice(0, 3).map((workflow) => (
                <div key={workflow.id} className="flex justify-between text-sm">
                  <span className="text-theme-secondary truncate max-w-[120px]">{workflow.name}</span>
                  <span className="font-medium text-theme-primary">${workflow.total_cost_usd.toFixed(2)}</span>
                </div>
              ))}
            </div>
          </div>
        </div>
      </Card>
    </div>
  );
};

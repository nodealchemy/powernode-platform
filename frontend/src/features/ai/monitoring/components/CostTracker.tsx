import React from 'react';
import { DollarSign, Clock } from 'lucide-react';
import { Card, CardTitle, CardContent } from '@/shared/components/ui/Card';
import type { WorkflowCostData } from '@/shared/types/workflow';

interface CostTrackerProps {
  costs: WorkflowCostData['costs'] | null;
  formatCurrency: (amount: number) => string;
}

export const CostTracker: React.FC<CostTrackerProps> = ({ costs, formatCurrency }) => (
  <Card>
    <CardTitle className="flex items-center gap-2 p-4 pb-0">
      <DollarSign className="h-5 w-5" />
      Cost Tracking
    </CardTitle>
    <CardContent className="space-y-4 pt-4">
      {costs ? (
        <>
          <div className="grid grid-cols-3 gap-4 text-sm">
            <div>
              <span className="text-theme-muted">Today</span>
              <p className="font-medium">{formatCurrency(costs.today)}</p>
            </div>
            <div>
              <span className="text-theme-muted">This Week</span>
              <p className="font-medium">{formatCurrency(costs.thisWeek)}</p>
            </div>
            <div>
              <span className="text-theme-muted">This Month</span>
              <p className="font-medium">{formatCurrency(costs.thisMonth)}</p>
            </div>
          </div>

          {costs.byProvider && Object.keys(costs.byProvider).length > 0 && (
            <div>
              <h4 className="text-sm font-medium mb-2">Cost by Provider</h4>
              <div className="space-y-2">
                {Object.entries(costs.byProvider).map(([provider, cost]) => (
                  <div key={provider} className="flex items-center justify-between text-sm">
                    <span className="capitalize">{provider}</span>
                    <span className="font-medium">{formatCurrency(cost)}</span>
                  </div>
                ))}
              </div>
            </div>
          )}

          {costs.byWorkflow && costs.byWorkflow.length > 0 && (
            <div>
              <h4 className="text-sm font-medium mb-2">Top Workflows by Cost</h4>
              <div className="space-y-2">
                {costs.byWorkflow.slice(0, 3).map(([workflow, cost]) => (
                  <div key={workflow} className="flex items-center justify-between text-sm">
                    <span className="truncate">{workflow}</span>
                    <span className="font-medium">{formatCurrency(cost)}</span>
                  </div>
                ))}
              </div>
            </div>
          )}
        </>
      ) : (
        <div className="text-center py-4 text-theme-muted">
          <Clock className="h-8 w-8 mx-auto mb-2 opacity-50" />
          <p>Loading cost data...</p>
        </div>
      )}
    </CardContent>
  </Card>
);

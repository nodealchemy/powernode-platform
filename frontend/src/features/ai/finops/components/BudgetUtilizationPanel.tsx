import React, { useState } from 'react';
import { Wallet, AlertTriangle } from 'lucide-react';
import { Card, CardHeader, CardContent } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { useBudgetUtilization } from '../api/finopsApi';
import type { BudgetParams } from '../types/finops';

const formatCost = (cost: number): string => {
  if (cost <= 0) return '$0.00';
  if (cost < 0.01) return `$${cost.toFixed(4)}`;
  if (cost >= 1000) return `$${(cost / 1000).toFixed(1)}K`;
  return `$${cost.toFixed(2)}`;
};

const ENTITY_FILTERS: { id: BudgetParams['entity_type'] | undefined; label: string }[] = [
  { id: undefined, label: 'All' },
  { id: 'agent', label: 'Agents' },
  { id: 'account', label: 'Accounts' },
  { id: 'team', label: 'Teams' },
];

export const BudgetUtilizationPanel: React.FC = () => {
  const [entityType, setEntityType] = useState<BudgetParams['entity_type'] | undefined>(undefined);
  const { data: budgets, isLoading } = useBudgetUtilization({ entity_type: entityType });

  if (isLoading) {
    return <LoadingSpinner size="sm" className="py-8" />;
  }

  if (!budgets || budgets.length === 0) {
    return (
      <EmptyState
        icon={Wallet}
        title="No budgets configured"
        description="Set up budgets for agents, teams, or accounts to track spending."
      />
    );
  }

  const sortedBudgets = [...budgets].sort((a, b) => b.utilization_pct - a.utilization_pct);

  return (
    <Card>
      <CardHeader
        title="Budget Utilization"
        action={
          <div className="flex items-center gap-1">
            {ENTITY_FILTERS.map((filter) => (
              <Button
                key={filter.label}
                variant={entityType === filter.id ? 'primary' : 'outline'}
                size="xs"
                onClick={() => setEntityType(filter.id)}
              >
                {filter.label}
              </Button>
            ))}
          </div>
        }
      />
      <CardContent>
        <div className="space-y-4">
          {sortedBudgets.map((budget) => {
            const utilizationColor = budget.utilization_pct >= 100
              ? 'bg-theme-error'
              : budget.utilization_pct >= budget.alert_threshold
                ? 'bg-theme-warning'
                : 'bg-theme-success';

            const utilizationTextColor = budget.utilization_pct >= 100
              ? 'text-theme-error'
              : budget.utilization_pct >= budget.alert_threshold
                ? 'text-theme-warning'
                : 'text-theme-success';

            return (
              <div key={budget.id} className="p-3 rounded-lg border border-theme bg-theme-surface">
                <div className="flex items-center justify-between mb-2">
                  <div className="flex items-center gap-2 min-w-0">
                    <span className="text-sm font-medium text-theme-primary truncate">
                      {budget.name}
                    </span>
                    <Badge
                      variant={
                        budget.entity_type === 'agent' ? 'info' :
                        budget.entity_type === 'team' ? 'warning' :
                        'default'
                      }
                      size="xs"
                    >
                      {budget.entity_type}
                    </Badge>
                    {budget.is_over_budget && (
                      <AlertTriangle className="h-4 w-4 text-theme-error flex-shrink-0" />
                    )}
                  </div>
                  <div className="flex items-center gap-3 text-right flex-shrink-0">
                    <span className={`text-sm font-semibold ${utilizationTextColor}`}>
                      {budget.utilization_pct.toFixed(1)}%
                    </span>
                  </div>
                </div>

                {/* Progress bar */}
                <div className="w-full bg-theme-accent rounded-full h-2 mb-2">
                  <div
                    className={`h-2 rounded-full ${utilizationColor} transition-all`}
                    style={{ width: `${Math.min(budget.utilization_pct, 100)}%` }}
                  />
                </div>

                {/* Details row */}
                <div className="flex items-center justify-between text-xs text-theme-tertiary">
                  <span>
                    {formatCost(budget.current_spend)} / {formatCost(budget.budget_limit)}
                  </span>
                  <span>
                    Projected: {formatCost(budget.projected_spend)}
                  </span>
                </div>
              </div>
            );
          })}
        </div>
      </CardContent>
    </Card>
  );
};

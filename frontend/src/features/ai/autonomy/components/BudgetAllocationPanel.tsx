import React from 'react';
import { DollarSign } from 'lucide-react';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { cn } from '@/shared/utils/cn';
import type { AgentBudget } from '../types/autonomy';

const formatCurrency = (cents: number, currency: string): string => {
  const amount = cents / 100;
  return new Intl.NumberFormat('en-US', { style: 'currency', currency }).format(amount);
};

const getUtilizationColor = (pct: number): string => {
  if (pct > 80) return 'bg-theme-error';
  if (pct > 60) return 'bg-theme-warning';
  return 'bg-theme-success';
};

const getUtilizationTextColor = (pct: number): string => {
  if (pct > 80) return 'text-theme-error';
  if (pct > 60) return 'text-theme-warning';
  return 'text-theme-success';
};

interface BudgetAllocationPanelProps {
  budgets: AgentBudget[];
}

export const BudgetAllocationPanel: React.FC<BudgetAllocationPanelProps> = ({ budgets }) => {
  if (budgets.length === 0) {
    return (
      <Card>
        <CardContent className="p-8 text-center text-theme-muted">
          <DollarSign className="w-12 h-12 mx-auto mb-3 opacity-30" />
          <p>No budget allocations configured.</p>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
      <CardHeader title="Budget Allocations" />
      <CardContent>
        <div className="space-y-4">
          {budgets.map((budget) => {
            const pct = Math.min(budget.utilization_percentage, 100);
            return (
              <div key={budget.id} className="p-3 rounded-lg bg-theme-surface border border-theme-border">
                <div className="flex items-center justify-between mb-2">
                  <div className="flex items-center gap-2">
                    <DollarSign className="h-4 w-4 text-theme-muted" />
                    <span className="text-sm font-medium text-theme-primary">{budget.agent_name}</span>
                    <span className="text-xs text-theme-muted capitalize">({budget.period_type})</span>
                  </div>
                  <span className={cn('text-sm font-semibold', getUtilizationTextColor(pct))}>
                    {Math.round(pct)}%
                  </span>
                </div>

                <div className="h-2 rounded-full bg-theme-border overflow-hidden mb-2">
                  <div
                    className={cn('h-full rounded-full transition-all', getUtilizationColor(pct))}
                    style={{ width: `${pct}%` }}
                  />
                </div>

                <div className="flex items-center justify-between text-xs text-theme-muted">
                  <span>Spent: {formatCurrency(budget.spent_cents, budget.currency)}</span>
                  <span>Total: {formatCurrency(budget.total_budget_cents, budget.currency)}</span>
                </div>
                {budget.reserved_cents > 0 && (
                  <div className="text-xs text-theme-muted mt-1">
                    Reserved: {formatCurrency(budget.reserved_cents, budget.currency)}
                    {' · '}
                    Remaining: {formatCurrency(budget.remaining_cents, budget.currency)}
                  </div>
                )}
              </div>
            );
          })}
        </div>
      </CardContent>
    </Card>
  );
};

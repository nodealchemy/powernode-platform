import React, { useState } from 'react';
import { DollarSign, Plus, Edit2, Trash2, ChevronDown, ChevronUp, AlertTriangle } from 'lucide-react';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { cn } from '@/shared/utils/cn';
import { useDeleteBudget } from '../api/autonomyApi';
import { BudgetTransactionHistory } from './BudgetTransactionHistory';
import { BudgetCreateEditModal } from './BudgetCreateEditModal';
import type { AgentBudget } from '../types/autonomy';

const formatCurrency = (cents: number, currency: string): string => {
  const amount = cents / 100;
  return new Intl.NumberFormat('en-US', { style: 'currency', currency }).format(amount);
};

const getUtilizationColor = (pct: number): string => {
  if (pct >= 100) return 'bg-theme-error';
  if (pct > 80) return 'bg-theme-warning';
  if (pct > 60) return 'bg-theme-warning';
  return 'bg-theme-success';
};

const getUtilizationTextColor = (pct: number): string => {
  if (pct >= 100) return 'text-theme-error';
  if (pct > 80) return 'text-theme-error';
  if (pct > 60) return 'text-theme-warning';
  return 'text-theme-success';
};

const getAlertBadge = (pct: number): React.ReactNode => {
  if (pct >= 100) return <Badge variant="default" size="sm"><AlertTriangle className="h-3 w-3 mr-1" />EXHAUSTED</Badge>;
  if (pct >= 90) return <Badge variant="warning" size="sm"><AlertTriangle className="h-3 w-3 mr-1" />90%+</Badge>;
  if (pct >= 75) return <Badge variant="info" size="sm">75%+</Badge>;
  return null;
};

interface BudgetAllocationPanelProps {
  budgets: AgentBudget[];
}

export const BudgetAllocationPanel: React.FC<BudgetAllocationPanelProps> = ({ budgets }) => {
  const [expandedBudgetId, setExpandedBudgetId] = useState<string | null>(null);
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [editingBudget, setEditingBudget] = useState<AgentBudget | null>(null);

  const deleteBudget = useDeleteBudget();

  const handleDelete = (budgetId: string) => {
    if (window.confirm('Are you sure you want to delete this budget?')) {
      deleteBudget.mutate(budgetId);
    }
  };

  const toggleExpand = (budgetId: string) => {
    setExpandedBudgetId(prev => prev === budgetId ? null : budgetId);
  };

  return (
    <>
      <Card>
        <CardHeader
          title="Budget Allocations"
          action={
            <button
              onClick={() => setShowCreateModal(true)}
              className="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium rounded-md bg-theme-info text-white hover:opacity-90 transition-opacity"
            >
              <Plus className="h-4 w-4" /> Create Budget
            </button>
          }
        />
        <CardContent>
          {budgets.length === 0 ? (
            <div className="p-8 text-center text-theme-muted">
              <DollarSign className="w-12 h-12 mx-auto mb-3 opacity-30" />
              <p>No budget allocations configured.</p>
            </div>
          ) : (
            <div className="space-y-3">
              {budgets.map((budget) => {
                const pct = Math.min(budget.utilization_percentage, 100);
                const isExpanded = expandedBudgetId === budget.id;
                return (
                  <div key={budget.id} className="rounded-lg bg-theme-surface border border-theme-border">
                    <div className="p-3">
                      <div className="flex items-center justify-between mb-2">
                        <div className="flex items-center gap-2">
                          <DollarSign className="h-4 w-4 text-theme-muted" />
                          <span className="text-sm font-medium text-theme-primary">{budget.agent_name}</span>
                          <span className="text-xs text-theme-muted capitalize">({budget.period_type})</span>
                          {getAlertBadge(budget.utilization_percentage)}
                        </div>
                        <div className="flex items-center gap-2">
                          <span className={cn('text-sm font-semibold', getUtilizationTextColor(budget.utilization_percentage))}>
                            {Math.round(budget.utilization_percentage)}%
                          </span>
                          <button
                            onClick={() => setEditingBudget(budget)}
                            className="p-1 rounded hover:bg-theme-bg-secondary text-theme-muted hover:text-theme-primary transition-colors"
                            title="Edit budget"
                          >
                            <Edit2 className="h-3.5 w-3.5" />
                          </button>
                          <button
                            onClick={() => handleDelete(budget.id)}
                            className="p-1 rounded hover:bg-theme-bg-secondary text-theme-muted hover:text-theme-error transition-colors"
                            title="Delete budget"
                          >
                            <Trash2 className="h-3.5 w-3.5" />
                          </button>
                          <button
                            onClick={() => toggleExpand(budget.id)}
                            className="p-1 rounded hover:bg-theme-bg-secondary text-theme-muted hover:text-theme-primary transition-colors"
                            title={isExpanded ? 'Collapse' : 'View transactions'}
                          >
                            {isExpanded ? <ChevronUp className="h-3.5 w-3.5" /> : <ChevronDown className="h-3.5 w-3.5" />}
                          </button>
                        </div>
                      </div>

                      <div className="h-2 rounded-full bg-theme-border overflow-hidden mb-2">
                        <div
                          className={cn('h-full rounded-full transition-all', getUtilizationColor(budget.utilization_percentage))}
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

                    {isExpanded && (
                      <div className="border-t border-theme-border p-3">
                        <BudgetTransactionHistory budgetId={budget.id} currency={budget.currency} />
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          )}
        </CardContent>
      </Card>

      {(showCreateModal || editingBudget) && (
        <BudgetCreateEditModal
          budget={editingBudget}
          onClose={() => {
            setShowCreateModal(false);
            setEditingBudget(null);
          }}
        />
      )}
    </>
  );
};

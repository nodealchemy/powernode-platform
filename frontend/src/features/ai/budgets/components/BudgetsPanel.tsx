import React, { useMemo, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { DollarSign, Plus, Edit2, Trash2, ChevronDown, ChevronUp, AlertTriangle, CornerDownRight, Split } from 'lucide-react';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { EntityLink } from '@/shared/components/entity';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { cn } from '@/shared/utils/cn';
import { useAutonomyStats } from '@/features/ai/autonomy/api/autonomyApi';
import { useAgentBudgets, useAllocateChildBudget, useDeleteBudget } from '../api/budgetsApi';
import { computeBudgetRegime } from '../budgetRegime';
import type { AgentBudget } from '../types';
import { BudgetAgentPicker } from './BudgetAgentPicker';
import { BudgetCreateEditModal } from './BudgetCreateEditModal';
import { BudgetRegimeIndicator } from './BudgetRegimeIndicator';
import { BudgetTransactionHistory } from './BudgetTransactionHistory';

/**
 * Agent budgets, one list. Reads and writes through /ai/autonomy/budgets only:
 * the list is gated on what that GET checks (ai.agents.read, the page's route
 * guard) and every write control on ai.autonomy.manage, which the write
 * actions check.
 *
 * Filters are the ones the data supports, all in the URL (?agent, ?period,
 * ?status) so a filtered view is linkable. Every budget is an AGENT budget —
 * there is no account or team budget to filter by.
 *
 * Self-contained: no page chrome, so it can be re-homed as is.
 */

type StatusFilter = '' | 'active' | 'exceeded' | 'expired';

const STATUS_OPTIONS: Array<{ value: StatusFilter; label: string }> = [
  { value: '', label: 'All' },
  { value: 'active', label: 'Active' },
  { value: 'exceeded', label: 'Exceeded' },
  { value: 'expired', label: 'Expired' },
];

const formatCurrency = (cents: number, currency = 'USD'): string =>
  new Intl.NumberFormat('en-US', { style: 'currency', currency }).format(cents / 100);

const isExpired = (budget: AgentBudget): boolean =>
  !!budget.period_end && new Date(budget.period_end).getTime() <= Date.now();

function matchesStatus(budget: AgentBudget, status: StatusFilter): boolean {
  if (status === 'active') return !isExpired(budget);
  if (status === 'expired') return isExpired(budget);
  if (status === 'exceeded') return budget.exceeded;
  return true;
}

/**
 * Parents in server order, each followed directly by the children allocated
 * from it, with each budget's depth in that tree. A child whose parent is not
 * in the list (filtered out) keeps its own place, at depth 0, rather than
 * disappearing.
 */
function nestUnderParents(budgets: AgentBudget[]): Array<{ budget: AgentBudget; depth: number }> {
  const ids = new Set(budgets.map((b) => b.id));
  const childrenOf = new Map<string, AgentBudget[]>();
  budgets.forEach((b) => {
    if (b.parent_budget_id && ids.has(b.parent_budget_id)) {
      childrenOf.set(b.parent_budget_id, [...(childrenOf.get(b.parent_budget_id) || []), b]);
    }
  });

  const ordered: Array<{ budget: AgentBudget; depth: number }> = [];
  const visit = (budget: AgentBudget, depth: number) => {
    ordered.push({ budget, depth });
    (childrenOf.get(budget.id) || []).forEach((child) => visit(child, depth + 1));
  };
  budgets
    .filter((b) => !(b.parent_budget_id && ids.has(b.parent_budget_id)))
    .forEach((b) => visit(b, 0));
  return ordered;
}

const utilizationBarColor = (pct: number): string => {
  if (pct >= 100) return 'bg-theme-error-bg';
  if (pct > 60) return 'bg-theme-warning-bg';
  return 'bg-theme-success-bg';
};

const utilizationTextColor = (pct: number): string => {
  if (pct > 80) return 'text-theme-error-fg';
  if (pct > 60) return 'text-theme-warning-fg';
  return 'text-theme-success-fg';
};

const alertBadge = (pct: number): React.ReactNode => {
  if (pct >= 100) return <Badge variant="default" size="sm"><AlertTriangle className="h-3 w-3 mr-1" />EXHAUSTED</Badge>;
  if (pct >= 90) return <Badge variant="warning" size="sm"><AlertTriangle className="h-3 w-3 mr-1" />90%+</Badge>;
  if (pct >= 75) return <Badge variant="info" size="sm">75%+</Badge>;
  return null;
};

const selectClass = 'px-2 py-1 text-sm rounded-md border border-theme bg-theme-surface text-theme-primary';

/** Carve part of a budget's remaining balance into a new child budget for another agent. */
const AllocateChildForm: React.FC<{ parent: AgentBudget; onDone: () => void }> = ({ parent, onDone }) => {
  const allocate = useAllocateChildBudget();
  const [agentId, setAgentId] = useState('');
  const [amount, setAmount] = useState('');
  const [error, setError] = useState<string | null>(null);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    const amountCents = Math.round(parseFloat(amount) * 100);
    if (!agentId) return setError('Choose the agent to allocate to.');
    if (isNaN(amountCents) || amountCents <= 0) return setError('Enter an amount greater than $0.');
    if (amountCents > parent.remaining_cents) {
      return setError(
        `That is more than the ${formatCurrency(parent.remaining_cents, parent.currency)} remaining on this budget.`
      );
    }
    allocate.mutate(
      { budgetId: parent.id, agentId, amountCents },
      {
        onSuccess: onDone,
        onError: (err: unknown) => {
          const serverMessage = (err as { response?: { data?: { error?: string } } })?.response?.data?.error;
          setError(serverMessage || (err instanceof Error ? err.message : 'Allocation failed.'));
        },
      }
    );
  };

  return (
    <form onSubmit={handleSubmit} className="border-t border-theme p-3 space-y-2" aria-label="Allocate to a child agent">
      <div className="flex flex-wrap items-end gap-2">
        <div className="text-xs text-theme-tertiary">
          <span>Child agent</span>
          <BudgetAgentPicker
            label="Child agent"
            value={agentId}
            onChange={setAgentId}
            excludeId={parent.agent_id}
            selectClassName={cn(selectClass, 'block mt-1 min-w-[12rem]')}
            searchClassName={cn(selectClass, 'block mt-1 min-w-[12rem]')}
          />
        </div>
        <label className="text-xs text-theme-tertiary">
          Amount ({parent.currency})
          <input
            aria-label={`Amount (${parent.currency})`}
            type="number"
            min="0.01"
            step="0.01"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            className={cn(selectClass, 'block mt-1 w-32')}
          />
        </label>
        <button type="submit" disabled={allocate.isPending} className="btn-theme btn-theme-primary btn-theme-sm">
          {allocate.isPending ? 'Allocating…' : 'Allocate budget'}
        </button>
        <button type="button" onClick={onDone} className="btn-theme btn-theme-secondary btn-theme-sm">Cancel</button>
      </div>
      <p className="text-xs text-theme-tertiary">
        {formatCurrency(parent.remaining_cents, parent.currency)} remaining. The amount is reserved on this budget.
      </p>
      {error && <p className="text-xs text-theme-error-fg">{error}</p>}
    </form>
  );
};

export const BudgetsPanel: React.FC = () => {
  const { hasPermission } = usePermissions();
  const canManage = hasPermission('ai.autonomy.manage');
  const { data: budgets, isLoading } = useAgentBudgets();
  const { data: stats } = useAutonomyStats();
  const deleteBudget = useDeleteBudget();
  const { confirm, ConfirmationDialog } = useConfirmation();
  const [searchParams, setSearchParams] = useSearchParams();

  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [allocatingId, setAllocatingId] = useState<string | null>(null);
  const [showCreate, setShowCreate] = useState(false);
  const [editing, setEditing] = useState<AgentBudget | null>(null);

  const agentFilter = searchParams.get('agent') ?? '';
  const periodFilter = searchParams.get('period') ?? '';
  const statusFilter = (searchParams.get('status') ?? '') as StatusFilter;

  const setFilter = (key: string, value: string) => {
    const next = new URLSearchParams(searchParams);
    if (value) next.set(key, value);
    else next.delete(key);
    setSearchParams(next, { replace: true });
  };

  const all = useMemo(() => budgets ?? [], [budgets]);
  const byId = useMemo(() => new Map(all.map((b) => [b.id, b])), [all]);
  const agentOptions = useMemo(
    () => Array.from(new Map(all.map((b) => [b.agent_id, b.agent_name])).entries())
      .sort(([, a], [, b]) => (a || '').localeCompare(b || '')),
    [all]
  );
  const periodOptions = useMemo(() => Array.from(new Set(all.map((b) => b.period_type))).sort(), [all]);

  const rows = useMemo(
    () => nestUnderParents(all.filter((b) =>
      (!agentFilter || b.agent_id === agentFilter) &&
      (!periodFilter || b.period_type === periodFilter) &&
      matchesStatus(b, statusFilter)
    )),
    [all, agentFilter, periodFilter, statusFilter]
  );

  const regime = computeBudgetRegime(stats);
  const filtering = !!(agentFilter || periodFilter || statusFilter);

  const handleDelete = (budget: AgentBudget) => {
    confirm({
      title: 'Delete budget',
      message: `Delete the budget for ${budget.agent_name || 'this agent'}? Its transaction history goes with it.`,
      confirmLabel: 'Delete',
      variant: 'danger',
      onConfirm: () => deleteBudget.mutateAsync(budget.id),
    });
  };

  return (
    <div className="space-y-4">
      {regime && <BudgetRegimeIndicator regime={regime} />}

      <Card>
        <CardHeader
          title="Agent Budgets"
          action={canManage ? (
            <button
              type="button"
              onClick={() => setShowCreate(true)}
              className="btn-theme btn-theme-primary btn-theme-sm inline-flex items-center gap-1.5"
            >
              <Plus className="h-4 w-4" /> Create Budget
            </button>
          ) : undefined}
        />
        <CardContent>
          <div role="group" aria-label="Budget filters" className="flex flex-wrap items-center gap-3 mb-4">
            <label className="flex items-center gap-2 text-xs text-theme-tertiary">
              Agent
              <select aria-label="Agent" value={agentFilter} onChange={(e) => setFilter('agent', e.target.value)} className={selectClass}>
                <option value="">All agents</option>
                {agentOptions.map(([id, name]) => <option key={id} value={id}>{name || id}</option>)}
              </select>
            </label>
            <label className="flex items-center gap-2 text-xs text-theme-tertiary">
              Period
              <select aria-label="Period" value={periodFilter} onChange={(e) => setFilter('period', e.target.value)} className={selectClass}>
                <option value="">All periods</option>
                {periodOptions.map((period) => <option key={period} value={period}>{period}</option>)}
              </select>
            </label>
            <label className="flex items-center gap-2 text-xs text-theme-tertiary">
              Status
              <select aria-label="Status" value={statusFilter} onChange={(e) => setFilter('status', e.target.value)} className={selectClass}>
                {STATUS_OPTIONS.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
              </select>
            </label>
          </div>

          {isLoading ? (
            <LoadingSpinner size="sm" className="py-8" />
          ) : rows.length === 0 ? (
            <div className="p-8 text-center text-theme-tertiary">
              <DollarSign className="w-12 h-12 mx-auto mb-3 opacity-30" />
              <p>{filtering ? 'No budgets match these filters.' : 'No agent budgets configured.'}</p>
            </div>
          ) : (
            <div className="space-y-3">
              {rows.map(({ budget, depth }) => {
                const nested = depth > 0;
                const parent = budget.parent_budget_id ? byId.get(budget.parent_budget_id) : undefined;
                const isExpanded = expandedId === budget.id;
                return (
                  <div
                    key={budget.id}
                    data-testid="budget-row"
                    data-depth={depth}
                    style={nested ? { marginLeft: `${depth * 1.5}rem` } : undefined}
                    className="rounded-lg bg-theme-surface border border-theme"
                  >
                    <div className="p-3">
                      <div className="flex items-center justify-between mb-2">
                        <div className="flex items-center gap-2 min-w-0">
                          {nested ? <CornerDownRight className="h-4 w-4 text-theme-tertiary" /> : <DollarSign className="h-4 w-4 text-theme-tertiary" />}
                          <span data-testid="budget-agent">
                            <EntityLink type="agent" id={budget.agent_id} label={budget.agent_name} className="text-sm font-medium" />
                          </span>
                          <span className="text-xs text-theme-tertiary capitalize">({budget.period_type})</span>
                          {isExpired(budget) && <Badge variant="default" size="sm">Expired</Badge>}
                          {alertBadge(budget.utilization_percentage)}
                        </div>
                        <div className="flex items-center gap-2">
                          <span className={cn('text-sm font-semibold', utilizationTextColor(budget.utilization_percentage))}>
                            {Math.round(budget.utilization_percentage)}%
                          </span>
                          {canManage && (
                            <>
                              <button
                                type="button"
                                onClick={() => setAllocatingId(allocatingId === budget.id ? null : budget.id)}
                                className="inline-flex items-center gap-1 px-2 py-0.5 text-xs rounded border border-theme text-theme-secondary hover:text-theme-primary"
                              >
                                <Split className="h-3 w-3" /> Allocate
                              </button>
                              <button type="button" onClick={() => setEditing(budget)} title="Edit budget"
                                className="p-1 rounded hover:bg-theme-background-secondary text-theme-tertiary hover:text-theme-primary">
                                <Edit2 className="h-3.5 w-3.5" />
                              </button>
                              <button type="button" onClick={() => handleDelete(budget)} title="Delete budget"
                                className="p-1 rounded hover:bg-theme-background-secondary text-theme-tertiary hover:text-theme-error-fg">
                                <Trash2 className="h-3.5 w-3.5" />
                              </button>
                            </>
                          )}
                          <button type="button" onClick={() => setExpandedId(isExpanded ? null : budget.id)}
                            title={isExpanded ? 'Hide transactions' : 'View transactions'}
                            className="p-1 rounded hover:bg-theme-background-secondary text-theme-tertiary hover:text-theme-primary">
                            {isExpanded ? <ChevronUp className="h-3.5 w-3.5" /> : <ChevronDown className="h-3.5 w-3.5" />}
                          </button>
                        </div>
                      </div>

                      {budget.parent_budget_id && (
                        <p className="text-xs text-theme-tertiary mb-2">
                          Allocated from {parent?.agent_name ?? 'another budget'}
                        </p>
                      )}

                      <div className="h-2 rounded-full bg-theme-background-secondary overflow-hidden mb-2">
                        <div
                          className={cn('h-full rounded-full transition-all', utilizationBarColor(budget.utilization_percentage))}
                          style={{ width: `${Math.min(budget.utilization_percentage, 100)}%` }}
                        />
                      </div>

                      <div className="flex items-center justify-between text-xs text-theme-tertiary">
                        <span>Spent: {formatCurrency(budget.spent_cents, budget.currency)}</span>
                        <span>Total: {formatCurrency(budget.total_budget_cents, budget.currency)}</span>
                      </div>
                      <div className="text-xs text-theme-tertiary mt-1">
                        Remaining: {formatCurrency(budget.remaining_cents, budget.currency)}
                        {budget.reserved_cents > 0 && (
                          <>{' · '}Reserved: {formatCurrency(budget.reserved_cents, budget.currency)}</>
                        )}
                      </div>
                    </div>

                    {allocatingId === budget.id && canManage && (
                      <AllocateChildForm parent={budget} onDone={() => setAllocatingId(null)} />
                    )}

                    {isExpanded && (
                      <div className="border-t border-theme p-3">
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

      {(showCreate || editing) && (
        <BudgetCreateEditModal
          budget={editing}
          onClose={() => {
            setShowCreate(false);
            setEditing(null);
          }}
        />
      )}
      {ConfirmationDialog}
    </div>
  );
};

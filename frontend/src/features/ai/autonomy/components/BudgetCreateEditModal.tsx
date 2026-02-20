import React, { useState } from 'react';
import { X } from 'lucide-react';
import { useCreateBudget, useUpdateBudget } from '../api/autonomyApi';
import type { AgentBudget } from '../types/autonomy';

interface BudgetCreateEditModalProps {
  budget?: AgentBudget | null;
  onClose: () => void;
}

export const BudgetCreateEditModal: React.FC<BudgetCreateEditModalProps> = ({ budget, onClose }) => {
  const isEdit = !!budget;
  const createBudget = useCreateBudget();
  const updateBudget = useUpdateBudget();

  const [agentId, setAgentId] = useState(budget?.agent_id ?? '');
  const [totalDollars, setTotalDollars] = useState(budget ? (budget.total_budget_cents / 100).toString() : '');
  const [currency, setCurrency] = useState(budget?.currency ?? 'USD');
  const [periodType, setPeriodType] = useState(budget?.period_type ?? 'monthly');
  const [error, setError] = useState<string | null>(null);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);

    const totalCents = Math.round(parseFloat(totalDollars) * 100);
    if (isNaN(totalCents) || totalCents <= 0) {
      setError('Please enter a valid budget amount greater than $0');
      return;
    }

    if (isEdit && budget) {
      updateBudget.mutate(
        { id: budget.id, total_budget_cents: totalCents, currency, period_type: periodType },
        { onSuccess: onClose, onError: (err: Error) => setError(err.message) }
      );
    } else {
      if (!agentId) {
        setError('Please enter an agent ID');
        return;
      }
      createBudget.mutate(
        { agent_id: agentId, total_budget_cents: totalCents, currency, period_type: periodType },
        { onSuccess: onClose, onError: (err: Error) => setError(err.message) }
      );
    }
  };

  const isPending = createBudget.isPending || updateBudget.isPending;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
      <div className="bg-theme-surface border border-theme-border rounded-xl shadow-xl w-full max-w-md mx-4">
        <div className="flex items-center justify-between p-4 border-b border-theme-border">
          <h3 className="text-lg font-semibold text-theme-primary">
            {isEdit ? 'Edit Budget' : 'Create Budget'}
          </h3>
          <button onClick={onClose} className="p-1 rounded hover:bg-theme-bg-secondary text-theme-muted">
            <X className="h-5 w-5" />
          </button>
        </div>

        <form onSubmit={handleSubmit} className="p-4 space-y-4">
          {!isEdit && (
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-1">Agent ID</label>
              <input
                type="text"
                value={agentId}
                onChange={(e) => setAgentId(e.target.value)}
                className="w-full rounded-md border border-theme bg-theme-bg-secondary text-theme-primary px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-theme-info"
                placeholder="Enter agent UUID"
                required
              />
            </div>
          )}

          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Total Budget ($)</label>
            <input
              type="number"
              step="0.01"
              min="0.01"
              value={totalDollars}
              onChange={(e) => setTotalDollars(e.target.value)}
              className="w-full rounded-md border border-theme bg-theme-bg-secondary text-theme-primary px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-theme-info"
              placeholder="10.00"
              required
            />
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-1">Currency</label>
              <select
                value={currency}
                onChange={(e) => setCurrency(e.target.value)}
                className="w-full rounded-md border border-theme bg-theme-bg-secondary text-theme-primary px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-theme-info"
              >
                <option value="USD">USD</option>
                <option value="EUR">EUR</option>
                <option value="GBP">GBP</option>
              </select>
            </div>
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-1">Period</label>
              <select
                value={periodType}
                onChange={(e) => setPeriodType(e.target.value)}
                className="w-full rounded-md border border-theme bg-theme-bg-secondary text-theme-primary px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-theme-info"
              >
                <option value="daily">Daily</option>
                <option value="weekly">Weekly</option>
                <option value="monthly">Monthly</option>
                <option value="total">Total (no period)</option>
              </select>
            </div>
          </div>

          {error && (
            <p className="text-sm text-theme-error">{error}</p>
          )}

          <div className="flex justify-end gap-2 pt-2">
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2 text-sm rounded-md border border-theme text-theme-primary hover:bg-theme-bg-secondary"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={isPending}
              className="px-4 py-2 text-sm rounded-md bg-theme-info text-white hover:opacity-90 disabled:opacity-50"
            >
              {isPending ? 'Saving...' : isEdit ? 'Update' : 'Create'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};

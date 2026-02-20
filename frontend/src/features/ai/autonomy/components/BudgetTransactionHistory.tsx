import React, { useState } from 'react';
import { ArrowDownCircle, ArrowUpCircle, RefreshCw, ChevronLeft, ChevronRight } from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';
import { useBudgetTransactions } from '../api/autonomyApi';
import type { BudgetTransaction } from '../types/autonomy';

const TRANSACTION_CONFIG: Record<string, { icon: React.ComponentType<{ className?: string }>; variant: 'success' | 'warning' | 'info' | 'default'; label: string }> = {
  debit: { icon: ArrowDownCircle, variant: 'warning', label: 'Debit' },
  credit: { icon: ArrowUpCircle, variant: 'success', label: 'Credit' },
  reservation: { icon: RefreshCw, variant: 'info', label: 'Reserved' },
  release: { icon: ArrowUpCircle, variant: 'info', label: 'Released' },
  rollover: { icon: RefreshCw, variant: 'default', label: 'Rollover' },
  adjustment: { icon: RefreshCw, variant: 'default', label: 'Adjustment' },
};

const formatCurrency = (cents: number, currency: string): string => {
  const amount = cents / 100;
  return new Intl.NumberFormat('en-US', { style: 'currency', currency }).format(amount);
};

interface BudgetTransactionHistoryProps {
  budgetId: string;
  currency: string;
}

export const BudgetTransactionHistory: React.FC<BudgetTransactionHistoryProps> = ({ budgetId, currency }) => {
  const [page, setPage] = useState(1);
  const { data, isLoading } = useBudgetTransactions(budgetId, page);

  if (isLoading) {
    return <p className="text-sm text-theme-muted py-2">Loading transactions...</p>;
  }

  const transactions = data?.transactions ?? [];
  const pagination = data?.pagination;

  if (transactions.length === 0) {
    return <p className="text-sm text-theme-muted py-2">No transactions recorded yet.</p>;
  }

  return (
    <div className="space-y-2">
      <h4 className="text-xs font-semibold text-theme-muted uppercase tracking-wide">Transaction History</h4>
      <div className="space-y-1.5">
        {transactions.map((txn: BudgetTransaction) => {
          const config = TRANSACTION_CONFIG[txn.transaction_type] || TRANSACTION_CONFIG.adjustment;
          const TxnIcon = config.icon;
          return (
            <div key={txn.id} className="flex items-center gap-3 py-1.5 text-sm">
              <TxnIcon className="h-4 w-4 text-theme-muted shrink-0" />
              <Badge variant={config.variant} size="sm">{config.label}</Badge>
              <span className="text-theme-primary font-medium">
                {txn.transaction_type === 'credit' ? '+' : '-'}{formatCurrency(Math.abs(txn.amount_cents), currency)}
              </span>
              <span className="text-theme-muted text-xs">
                Balance: {formatCurrency(txn.running_balance_cents, currency)}
              </span>
              <span className="text-theme-muted text-xs ml-auto">
                {new Date(txn.created_at).toLocaleString()}
              </span>
            </div>
          );
        })}
      </div>

      {pagination && pagination.total_pages > 1 && (
        <div className="flex items-center justify-between pt-2 border-t border-theme-border">
          <span className="text-xs text-theme-muted">
            Page {pagination.page} of {pagination.total_pages} ({pagination.total} total)
          </span>
          <div className="flex gap-1">
            <button
              onClick={() => setPage(p => Math.max(1, p - 1))}
              disabled={page <= 1}
              className="p-1 rounded hover:bg-theme-bg-secondary text-theme-muted disabled:opacity-30"
            >
              <ChevronLeft className="h-4 w-4" />
            </button>
            <button
              onClick={() => setPage(p => Math.min(pagination.total_pages, p + 1))}
              disabled={page >= pagination.total_pages}
              className="p-1 rounded hover:bg-theme-bg-secondary text-theme-muted disabled:opacity-30"
            >
              <ChevronRight className="h-4 w-4" />
            </button>
          </div>
        </div>
      )}
    </div>
  );
};

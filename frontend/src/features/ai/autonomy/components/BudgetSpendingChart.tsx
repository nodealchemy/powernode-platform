import React, { useMemo } from 'react';
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, Cell } from 'recharts';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useBudgetTransactions } from '../api/autonomyApi';

interface BudgetSpendingChartProps {
  budgetId: string;
  currency: string;
  totalBudgetCents: number;
}

const formatDollars = (cents: number): string => `$${(cents / 100).toFixed(2)}`;

export const BudgetSpendingChart: React.FC<BudgetSpendingChartProps> = ({
  budgetId,
  currency,
  totalBudgetCents,
}) => {
  const { data, isLoading } = useBudgetTransactions(budgetId, 1, 100);

  const chartData = useMemo(() => {
    const transactions = data?.transactions ?? [];
    if (transactions.length === 0) return [];

    const debits = transactions.filter((t) => t.transaction_type === 'debit');
    const byDay = new Map<string, number>();

    for (const txn of debits) {
      const day = new Date(txn.created_at).toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
      byDay.set(day, (byDay.get(day) ?? 0) + txn.amount_cents);
    }

    return Array.from(byDay.entries()).map(([day, cents]) => ({
      day,
      spent: cents,
      label: formatDollars(cents),
    }));
  }, [data]);

  if (isLoading) {
    return <LoadingSpinner size="sm" className="py-4" />;
  }

  if (chartData.length === 0) {
    return null;
  }

  const budgetDollars = totalBudgetCents / 100;

  return (
    <Card>
      <CardHeader title="Spending by Day" />
      <CardContent>
        <div className="h-48">
          <ResponsiveContainer width="100%" height="100%">
            <BarChart data={chartData} margin={{ top: 4, right: 4, left: 4, bottom: 4 }}>
              <XAxis
                dataKey="day"
                tick={{ fontSize: 11, fill: 'var(--theme-text-muted)' }}
                axisLine={false}
                tickLine={false}
              />
              <YAxis
                tickFormatter={(v: number) => `$${(v / 100).toFixed(0)}`}
                tick={{ fontSize: 11, fill: 'var(--theme-text-muted)' }}
                axisLine={false}
                tickLine={false}
                width={48}
              />
              <Tooltip
                formatter={(value: number | string | undefined) => [formatDollars(Number(value ?? 0)), 'Spent']}
                contentStyle={{
                  backgroundColor: 'var(--theme-bg-surface)',
                  borderColor: 'var(--theme-border)',
                  borderRadius: '0.5rem',
                  fontSize: '0.75rem',
                }}
              />
              <Bar dataKey="spent" radius={[4, 4, 0, 0]}>
                {chartData.map((entry, index) => (
                  <Cell
                    key={index}
                    fill={entry.spent > budgetDollars * 100 * 0.2
                      ? 'var(--theme-error, #ef4444)'
                      : 'var(--theme-info, #3b82f6)'}
                  />
                ))}
              </Bar>
            </BarChart>
          </ResponsiveContainer>
        </div>
        <p className="text-xs text-theme-muted text-center mt-2">
          Budget: {formatDollars(totalBudgetCents)} ({currency})
        </p>
      </CardContent>
    </Card>
  );
};

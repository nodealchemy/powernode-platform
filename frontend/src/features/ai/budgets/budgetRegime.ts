import type { AutonomyStats } from '@/features/ai/autonomy/types/autonomy';
import type { BudgetRegime } from './types';

/**
 * The budget regime from aggregate agent spend (the autonomy stats' active
 * budgets). ONE definition of the bands, shared by every surface that shows a
 * BudgetRegimeIndicator, so they cannot disagree about the same account.
 */
export function computeBudgetRegime(stats: AutonomyStats | undefined | null): BudgetRegime | null {
  const budgets = stats?.budgets;
  if (!budgets || budgets.total_budget_cents === 0) return null;

  const pct = (budgets.total_spent_cents / budgets.total_budget_cents) * 100;
  const remaining = budgets.total_budget_cents - budgets.total_spent_cents;

  let level: BudgetRegime['level'];
  let message: string;
  if (pct >= 100) {
    level = 'EXHAUSTED';
    message = 'Budget exhausted — new executions blocked';
  } else if (pct >= 80) {
    level = 'CRITICAL';
    message = 'Budget is critically low — only essential operations permitted';
  } else if (pct >= 50) {
    level = 'CAUTIOUS';
    message = 'Budget utilization is moderate';
  } else {
    level = 'NORMAL';
    message = 'Budget availability is healthy';
  }

  return { level, utilization_pct: pct, remaining_cents: remaining, message };
}

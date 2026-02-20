import React from 'react';
import { DollarSign } from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';
import type { BudgetRegime } from '../types/autonomy';

interface BudgetRegimeIndicatorProps {
  regime: BudgetRegime;
}

const REGIME_CONFIG: Record<BudgetRegime['level'], { variant: 'success' | 'info' | 'warning' | 'default'; label: string }> = {
  NORMAL: { variant: 'success', label: 'Normal' },
  CAUTIOUS: { variant: 'info', label: 'Cautious' },
  CRITICAL: { variant: 'warning', label: 'Critical' },
  EXHAUSTED: { variant: 'default', label: 'Exhausted' },
};

export const BudgetRegimeIndicator: React.FC<BudgetRegimeIndicatorProps> = ({ regime }) => {
  const config = REGIME_CONFIG[regime.level];

  return (
    <div className="flex items-center gap-3 p-3 rounded-lg bg-theme-surface border border-theme-border">
      <div className="h-8 w-8 rounded-lg flex items-center justify-center bg-theme-bg-secondary">
        <DollarSign className="h-4 w-4 text-theme-muted" />
      </div>
      <div className="flex-1">
        <div className="flex items-center gap-2">
          <span className="text-sm font-medium text-theme-primary">Budget Regime</span>
          <Badge variant={config.variant} size="sm">{config.label}</Badge>
        </div>
        <p className="text-xs text-theme-muted mt-0.5">{regime.message}</p>
      </div>
      <div className="text-right">
        <p className="text-sm font-semibold text-theme-primary">{regime.utilization_pct.toFixed(1)}%</p>
        <p className="text-xs text-theme-muted">used</p>
      </div>
    </div>
  );
};

import React, { useMemo } from 'react';
import { DollarSign, TrendingUp, TrendingDown } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import type { CostEstimate, CostConfidence } from './types';

export interface CostBreakdownProps {
  estimate: CostEstimate;
  /**
   * Optional "before" estimate. When supplied, the panel renders a two-column
   * before/after diff (used for M2 adaptation flows; rare in M1).
   */
  previousEstimate?: CostEstimate;
  className?: string;
}

const CONFIDENCE_VARIANT: Record<CostConfidence, 'success' | 'warning' | 'danger'> = {
  high: 'success',
  med: 'warning',
  low: 'danger'
};

const CONFIDENCE_LABEL: Record<CostConfidence, string> = {
  high: 'High confidence',
  med: 'Medium confidence',
  low: 'Low confidence'
};

interface CategoryTotal {
  label: string;
  monthly: number;
  count: number;
}

/**
 * Heuristic resource_type → category bucket. Backend emits free-form types
 * (e.g. `compute.vm`, `volume`, `cache.redis`) so we substring-match. Anything
 * that doesn't match falls into the `Other` bucket — visible but unbucketed.
 */
const CATEGORY_RULES: Array<{ keywords: string[]; label: string }> = [
  { keywords: ['compute', 'vm', 'instance', 'cpu'], label: 'Compute' },
  { keywords: ['volume', 'storage', 'disk', 'object_store'], label: 'Storage' },
  { keywords: ['database', 'db', 'postgres', 'mysql'], label: 'Database' },
  { keywords: ['cache', 'redis', 'memcache'], label: 'Cache' },
  { keywords: ['network', 'gateway', 'load_balancer', 'lb', 'cdn', 'egress'], label: 'Network' }
];

const bucketFor = (resourceType: string): string => {
  const normalized = resourceType.toLowerCase();
  for (const rule of CATEGORY_RULES) {
    if (rule.keywords.some((kw) => normalized.includes(kw))) return rule.label;
  }
  return 'Other';
};

const formatUsd = (value: number): string => {
  return `$${Math.abs(value).toLocaleString(undefined, { maximumFractionDigits: 2 })}`;
};

/**
 * CostBreakdown — provisioning-aware cost panel.
 *
 * Replaces the generic `CostMetricsPanel` for the plan-review surface. Always
 * renders one column (current plan); the second column appears only when a
 * previous estimate is provided so adaptation flows can show savings vs. the
 * existing footprint at a glance.
 */
export const CostBreakdown: React.FC<CostBreakdownProps> = ({
  estimate,
  previousEstimate,
  className = ''
}) => {
  const categoryTotals = useMemo<CategoryTotal[]>(() => {
    const totals = new Map<string, CategoryTotal>();
    for (const resource of estimate.by_resource ?? []) {
      const label = bucketFor(resource.resource_type);
      const current = totals.get(label) ?? { label, monthly: 0, count: 0 };
      current.monthly += resource.monthly_usd;
      current.count += resource.count;
      totals.set(label, current);
    }
    return Array.from(totals.values()).sort((a, b) => b.monthly - a.monthly);
  }, [estimate]);

  const confidenceVariant = CONFIDENCE_VARIANT[estimate.confidence];
  const confidenceLabel = CONFIDENCE_LABEL[estimate.confidence];
  const lastPriced = estimate.last_priced_at
    ? new Date(estimate.last_priced_at).toLocaleString()
    : null;
  const confidenceTitle = lastPriced
    ? `Last priced: ${lastPriced}`
    : 'Pricing sync timestamp unavailable';

  const monthlyDelta = previousEstimate
    ? estimate.monthly_usd - previousEstimate.monthly_usd
    : null;

  return (
    <Card variant="default" padding="md" className={className} data-testid="cost-breakdown">
      <div className="flex items-center justify-between mb-3">
        <div className="flex items-center gap-2">
          <DollarSign className="w-4 h-4 text-theme-interactive-primary" />
          <h4 className="text-sm font-semibold text-theme-primary">Cost estimate</h4>
        </div>
        <span
          title={confidenceTitle}
          className="cursor-help"
          data-testid="cost-confidence-pill"
        >
          <Badge variant={confidenceVariant} size="sm">
            {confidenceLabel}
          </Badge>
        </span>
      </div>

      <div className={previousEstimate ? 'grid grid-cols-2 gap-3' : ''}>
        {previousEstimate && (
          <div
            className="rounded-lg bg-theme-background-secondary p-3"
            data-testid="cost-previous"
          >
            <p className="text-xs text-theme-tertiary mb-1">Before</p>
            <p className="text-sm text-theme-secondary">
              {formatUsd(previousEstimate.monthly_usd)}/mo
            </p>
            <p className="text-xs text-theme-tertiary mt-0.5">
              + {formatUsd(previousEstimate.one_time_usd)} one-time
            </p>
          </div>
        )}
        <div
          className="rounded-lg bg-theme-interactive-primary/10 p-3"
          data-testid="cost-current"
        >
          {previousEstimate && <p className="text-xs text-theme-tertiary mb-1">After</p>}
          <ul className="space-y-1">
            {categoryTotals.map((cat) => (
              <li
                key={cat.label}
                className="flex items-center justify-between text-xs"
                data-testid={`cost-category-${cat.label.toLowerCase()}`}
              >
                <span className="text-theme-secondary">
                  {cat.label}
                  {cat.count > 0 && (cat.label === 'Compute' || cat.label === 'Database') && (
                    <span className="text-theme-tertiary">
                      {' · '}
                      {cat.count} {cat.label === 'Compute' ? 'instance' : 'instance'}
                      {cat.count === 1 ? '' : 's'}
                    </span>
                  )}
                </span>
                <span className="font-medium text-theme-primary">
                  {formatUsd(cat.monthly)}/mo
                </span>
              </li>
            ))}
            {categoryTotals.length === 0 && (
              <li className="text-xs text-theme-tertiary italic">
                No itemized breakdown.
              </li>
            )}
          </ul>
          <div className="border-t border-theme mt-2 pt-2 space-y-0.5">
            <div className="flex items-center justify-between text-sm">
              <span className="text-theme-secondary">Total monthly</span>
              <span
                className="font-semibold text-theme-primary"
                data-testid="cost-total-monthly"
              >
                {formatUsd(estimate.monthly_usd)}/mo
              </span>
            </div>
            <div className="flex items-center justify-between text-xs">
              <span className="text-theme-tertiary">One-time</span>
              <span
                className="text-theme-secondary"
                data-testid="cost-total-onetime"
              >
                {formatUsd(estimate.one_time_usd)}
              </span>
            </div>
            {monthlyDelta !== null && (
              <div
                className={`flex items-center gap-1 text-xs mt-1 ${
                  monthlyDelta > 0
                    ? 'text-theme-warning'
                    : monthlyDelta < 0
                      ? 'text-theme-success'
                      : 'text-theme-tertiary'
                }`}
                data-testid="cost-delta"
              >
                {monthlyDelta > 0 ? (
                  <TrendingUp className="w-3 h-3" />
                ) : monthlyDelta < 0 ? (
                  <TrendingDown className="w-3 h-3" />
                ) : null}
                <span>
                  {monthlyDelta > 0 ? '+' : monthlyDelta < 0 ? '−' : ''}
                  {formatUsd(monthlyDelta)}/mo
                  {monthlyDelta > 0 ? ' increase' : monthlyDelta < 0 ? ' savings' : ' (no change)'}
                </span>
              </div>
            )}
          </div>
        </div>
      </div>
    </Card>
  );
};

export default CostBreakdown;

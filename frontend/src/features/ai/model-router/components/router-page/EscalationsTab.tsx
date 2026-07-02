import React from 'react';
import { ArrowUpRight, AlertTriangle } from 'lucide-react';
import {
  EscalationDecision,
  EscalationRollup,
  EscalationBenefit,
  EscalationBenefitBucket,
  EscalationBenefitAdvisory,
  EscalationTier,
  EscalationTimeRange
} from '@/shared/services/ai/ModelRouterApiService';

interface EscalationsTabProps {
  escalations: EscalationDecision[];
  rollup: EscalationRollup | null;
  benefit: EscalationBenefit | null;
  loading: boolean;
  tierFilter: EscalationTier | 'all';
  timeRange: EscalationTimeRange;
  onTierChange: (tier: EscalationTier | 'all') => void;
  onTimeRangeChange: (range: EscalationTimeRange) => void;
}

const TIME_RANGE_OPTIONS: Array<{ value: EscalationTimeRange; label: string }> = [
  { value: '1h', label: 'Last hour' },
  { value: '6h', label: 'Last 6 hours' },
  { value: '24h', label: 'Last 24 hours' },
  { value: '7d', label: 'Last 7 days' },
  { value: '30d', label: 'Last 30 days' },
  { value: '90d', label: 'Last 90 days' }
];

const getTierColor = (tier: string | null): string => {
  switch (tier) {
    case 'frontier': return 'text-theme-danger-fg bg-theme-danger-fg/10';
    case 'reasoning': return 'text-theme-warning-fg bg-theme-warning-fg/10';
    case 'standard': return 'text-theme-info-fg bg-theme-info-fg/10';
    case 'light': return 'text-theme-success-fg bg-theme-success-fg/10';
    default: return 'text-theme-secondary bg-theme-surface';
  }
};

const getOutcomeColor = (outcome: string | null): string => {
  switch (outcome) {
    case 'succeeded': return 'text-theme-success-fg bg-theme-success-fg/10';
    case 'failed': return 'text-theme-danger-fg bg-theme-danger-fg/10';
    case 'error': return 'text-theme-danger-fg bg-theme-danger-fg/10';
    case 'timeout': return 'text-theme-warning-fg bg-theme-warning-fg/10';
    default: return 'text-theme-secondary bg-theme-surface';
  }
};

const formatDelta = (value: number | null, unit: string, precision = 2): string => {
  if (value == null) return '—';
  const sign = value > 0 ? '+' : '';
  return `${sign}${value.toFixed(precision)}${unit}`;
};

const deltaTone = (value: number | null, positiveIsGood: boolean): string => {
  if (value == null || value === 0) return 'text-theme-primary';
  const good = positiveIsGood ? value > 0 : value < 0;
  return good ? 'text-theme-success-fg' : 'text-theme-danger-fg';
};

const AdvisoryBanner: React.FC<{ advisory: EscalationBenefitAdvisory }> = ({ advisory }) => {
  if (!advisory.recommend_tightening) return null;
  return (
    <div className="flex items-start gap-3 p-4 rounded-lg border border-theme-warning-border bg-theme-warning-fg/10">
      <AlertTriangle size={18} className="text-theme-warning-fg mt-0.5 flex-shrink-0" />
      <div>
        <p className="text-sm font-semibold text-theme-warning-fg">Escalation tightening recommended</p>
        <p className="text-sm text-theme-primary mt-1">{advisory.message}</p>
      </div>
    </div>
  );
};

const RollupCard: React.FC<{ label: string; value: string; sub?: string }> = ({ label, value, sub }) => (
  <div className="bg-theme-surface border border-theme rounded-lg p-4">
    <p className="text-sm text-theme-secondary">{label}</p>
    <p className="text-2xl font-bold text-theme-primary">{value}</p>
    {sub && <p className="text-xs text-theme-secondary mt-1">{sub}</p>}
  </div>
);

const CategoryList: React.FC<{ title: string; counts: Record<string, number> }> = ({ title, counts }) => {
  const entries = Object.entries(counts).sort(([, a], [, b]) => b - a).slice(0, 5);
  return (
    <div>
      <p className="text-xs font-medium text-theme-tertiary uppercase tracking-wide mb-2">{title}</p>
      {entries.length === 0 ? (
        <p className="text-sm text-theme-secondary">No data</p>
      ) : (
        <ul className="space-y-1">
          {entries.map(([category, count]) => (
            <li key={category} className="flex items-center justify-between text-sm">
              <span className="text-theme-primary">{category.replace(/_/g, ' ')}</span>
              <span className="text-theme-secondary font-mono">{count.toLocaleString()}</span>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
};

const BenefitBucketRow: React.FC<{ bucket: EscalationBenefitBucket }> = ({ bucket }) => (
  <tr className="hover:bg-theme-surface-hover transition-colors">
    <td className="px-4 py-3 text-sm text-theme-primary">{bucket.task_type || '—'}</td>
    <td className="px-4 py-3 text-sm text-theme-primary">{bucket.complexity_level || '—'}</td>
    <td className="px-4 py-3 text-sm text-right text-theme-secondary">
      {bucket.escalated.decisions.toLocaleString()} / {bucket.standard.decisions.toLocaleString()}
    </td>
    <td className={`px-4 py-3 text-sm text-right ${deltaTone(bucket.deltas.success_rate, true)}`}>
      {formatDelta(bucket.deltas.success_rate, '%')}
    </td>
    <td className={`px-4 py-3 text-sm text-right ${deltaTone(bucket.deltas.avg_cost_usd, false)}`}>
      {bucket.deltas.avg_cost_usd != null ? `${bucket.deltas.avg_cost_usd > 0 ? '+' : ''}$${bucket.deltas.avg_cost_usd.toFixed(6)}` : '—'}
    </td>
    <td className={`px-4 py-3 text-sm text-right ${deltaTone(bucket.deltas.avg_latency_ms, false)}`}>
      {formatDelta(bucket.deltas.avg_latency_ms, 'ms')}
    </td>
    <td className="px-4 py-3 text-sm text-center">
      {bucket.matched ? (
        <span className="px-2 py-0.5 text-xs rounded text-theme-success-fg bg-theme-success-fg/10">matched</span>
      ) : (
        <span className="px-2 py-0.5 text-xs rounded text-theme-secondary bg-theme-surface">unmatched</span>
      )}
    </td>
  </tr>
);

export const EscalationsTab: React.FC<EscalationsTabProps> = ({
  escalations,
  rollup,
  benefit,
  loading,
  tierFilter,
  timeRange,
  onTierChange,
  onTimeRangeChange
}) => {
  const advisory = rollup?.advisory ?? benefit?.advisory ?? null;

  if (loading) {
    return (
      <div className="text-center py-12">
        <div className="inline-block animate-spin rounded-full h-8 w-8 border-4 border-theme-info-border border-t-theme-primary"></div>
        <p className="mt-4 text-theme-secondary">Loading escalation data...</p>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Advisory banner (report-only: fires on recommend_tightening) */}
      {advisory && <AdvisoryBanner advisory={advisory} />}

      {/* Filters */}
      <div className="flex flex-wrap items-center gap-3">
        <select
          value={tierFilter}
          onChange={(e) => onTierChange(e.target.value as EscalationTier | 'all')}
          aria-label="Filter by tier"
          className="px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary text-sm focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
        >
          <option value="all">All escalated tiers</option>
          <option value="frontier">Frontier</option>
          <option value="reasoning">Reasoning</option>
        </select>
        <select
          value={timeRange}
          onChange={(e) => onTimeRangeChange(e.target.value as EscalationTimeRange)}
          aria-label="Filter by time range"
          className="px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary text-sm focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
        >
          {TIME_RANGE_OPTIONS.map(opt => (
            <option key={opt.value} value={opt.value}>{opt.label}</option>
          ))}
        </select>
      </div>

      {/* Rollup cards */}
      {rollup && (
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
          <RollupCard
            label="Escalated Decisions"
            value={rollup.escalated_decisions.toLocaleString()}
            sub={`of ${rollup.total_decisions.toLocaleString()} decisions (${rollup.period_days}d window)`}
          />
          <RollupCard
            label="Frontier Selections"
            value={rollup.selections.frontier.toLocaleString()}
            sub={`${rollup.selections.reasoning.toLocaleString()} reasoning`}
          />
          <RollupCard
            label="High-Effort Selections"
            value={rollup.selections.high_effort.toLocaleString()}
          />
          <RollupCard
            label="Escalated Spend Share"
            value={`${rollup.spend.escalated_share_pct.toFixed(2)}%`}
            sub={`$${rollup.spend.escalated_usd.toFixed(4)} of $${rollup.spend.total_usd.toFixed(4)}`}
          />
        </div>
      )}

      {/* Top rationale categories */}
      {rollup && (
        <div className="bg-theme-surface border border-theme rounded-lg p-6">
          <h3 className="text-lg font-semibold text-theme-primary mb-4">Top Rationale Categories</h3>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
            <CategoryList title="By Complexity Level" counts={rollup.top_rationale_categories.by_complexity_level} />
            <CategoryList title="By Task Type" counts={rollup.top_rationale_categories.by_task_type} />
            <CategoryList title="By Decision Kind" counts={rollup.top_rationale_categories.by_decision_kind} />
          </div>
        </div>
      )}

      {/* Escalation decisions table */}
      {escalations.length === 0 ? (
        <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
          <ArrowUpRight size={48} className="mx-auto text-theme-secondary mb-4" />
          <h3 className="text-lg font-semibold text-theme-primary mb-2">No escalations</h3>
          <p className="text-theme-secondary">Escalated routing decisions will appear here as governed requests are processed</p>
        </div>
      ) : (
        <div className="bg-theme-surface border border-theme rounded-lg overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead>
                <tr className="border-b border-theme bg-theme-surface">
                  <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase">Time</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase">Tier</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase">Model</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase">Effort</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase">Task Type</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase">Rationale</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase">Outcome</th>
                  <th className="px-4 py-3 text-right text-xs font-medium text-theme-secondary uppercase">Cost</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-theme">
                {escalations.map(escalation => (
                  <tr key={escalation.id} className="hover:bg-theme-surface-hover transition-colors">
                    <td className="px-4 py-3 text-sm text-theme-secondary whitespace-nowrap">
                      {new Date(escalation.created_at).toLocaleString()}
                    </td>
                    <td className="px-4 py-3">
                      <span className={`px-2 py-1 text-xs rounded ${getTierColor(escalation.model_tier)}`}>
                        {escalation.model_tier || 'unknown'}
                      </span>
                      {escalation.baseline_tier && escalation.baseline_tier !== escalation.model_tier && (
                        <span className="block mt-1 text-xs text-theme-tertiary">from {escalation.baseline_tier}</span>
                      )}
                    </td>
                    <td className="px-4 py-3 text-sm font-mono text-theme-primary">{escalation.delivered_model || '—'}</td>
                    <td className="px-4 py-3 text-sm text-theme-primary">{escalation.effort || '—'}</td>
                    <td className="px-4 py-3 text-sm text-theme-primary">
                      {escalation.task_type || '—'}
                      {escalation.complexity_level && (
                        <span className="block text-xs text-theme-tertiary">{escalation.complexity_level}</span>
                      )}
                    </td>
                    <td className="px-4 py-3 text-sm text-theme-secondary max-w-md">
                      <span className="line-clamp-2">{escalation.rationale_summary || '—'}</span>
                    </td>
                    <td className="px-4 py-3">
                      <span className={`px-2 py-1 text-xs rounded ${getOutcomeColor(escalation.outcome)}`}>
                        {escalation.outcome || 'pending'}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-sm text-right text-theme-secondary whitespace-nowrap">
                      {escalation.cost_usd != null ? `$${escalation.cost_usd.toFixed(4)}` : '—'}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Benefit deltas */}
      {benefit && (
        <div className="bg-theme-surface border border-theme rounded-lg p-6">
          <h3 className="text-lg font-semibold text-theme-primary mb-1">Escalation Benefit</h3>
          <p className="text-sm text-theme-secondary mb-4">
            Escalated vs standard-tier cohorts, controlled by task type and complexity level
            ({benefit.summary.matched_buckets} of {benefit.summary.total_buckets} buckets comparable)
          </p>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
            <div className="p-3 bg-theme-background border border-theme rounded-lg">
              <p className="text-xs text-theme-secondary">Success Rate Delta</p>
              <p className={`text-lg font-semibold ${deltaTone(benefit.summary.success_rate_delta, true)}`}>
                {formatDelta(benefit.summary.success_rate_delta, '%')}
              </p>
              <p className="text-xs text-theme-tertiary mt-1">
                {benefit.summary.escalated_success_rate != null ? `${benefit.summary.escalated_success_rate.toFixed(2)}%` : '—'} escalated vs{' '}
                {benefit.summary.standard_success_rate != null ? `${benefit.summary.standard_success_rate.toFixed(2)}%` : '—'} standard
              </p>
            </div>
            <div className="p-3 bg-theme-background border border-theme rounded-lg">
              <p className="text-xs text-theme-secondary">Avg Cost Delta</p>
              <p className={`text-lg font-semibold ${deltaTone(benefit.summary.avg_cost_delta, false)}`}>
                {benefit.summary.avg_cost_delta != null
                  ? `${benefit.summary.avg_cost_delta > 0 ? '+' : ''}$${benefit.summary.avg_cost_delta.toFixed(6)}`
                  : '—'}
              </p>
            </div>
            <div className="p-3 bg-theme-background border border-theme rounded-lg">
              <p className="text-xs text-theme-secondary">Avg Latency Delta</p>
              <p className={`text-lg font-semibold ${deltaTone(benefit.summary.avg_latency_delta, false)}`}>
                {formatDelta(benefit.summary.avg_latency_delta, 'ms')}
              </p>
            </div>
          </div>

          {benefit.advisory && !benefit.advisory.recommend_tightening && (
            <p className="text-sm text-theme-secondary mb-4">{benefit.advisory.message}</p>
          )}

          {benefit.buckets.length > 0 && (
            <div className="overflow-x-auto border border-theme rounded-lg">
              <table className="w-full">
                <thead>
                  <tr className="border-b border-theme bg-theme-surface">
                    <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase">Task Type</th>
                    <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase">Complexity</th>
                    <th className="px-4 py-3 text-right text-xs font-medium text-theme-secondary uppercase">Esc / Std</th>
                    <th className="px-4 py-3 text-right text-xs font-medium text-theme-secondary uppercase">Success Δ</th>
                    <th className="px-4 py-3 text-right text-xs font-medium text-theme-secondary uppercase">Cost Δ</th>
                    <th className="px-4 py-3 text-right text-xs font-medium text-theme-secondary uppercase">Latency Δ</th>
                    <th className="px-4 py-3 text-center text-xs font-medium text-theme-secondary uppercase">Comparable</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-theme">
                  {benefit.buckets.map((bucket, idx) => (
                    <BenefitBucketRow key={`${bucket.task_type}-${bucket.complexity_level}-${idx}`} bucket={bucket} />
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}
    </div>
  );
};

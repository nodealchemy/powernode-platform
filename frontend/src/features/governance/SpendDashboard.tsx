import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { AlertTriangle, RefreshCw, TrendingUp } from 'lucide-react';
import { logger } from '@/shared/utils/logger';
import { EntityLink } from '@/shared/components/entity';
import { governanceSpendApi } from './services/governanceSpendApi';

/**
 * SpendDashboard — M4 Enterprise governance pane.
 *
 * Surfaces month-to-date spend (compute + LLM) against the active
 * plan's combined cap, with a per-mission breakdown of the top five
 * cost contributors and alert chips when the account is within 10%
 * of its monthly cap.
 *
 * Data is fetched from `/governance/spend` (server-side aggregation
 * lives behind that route — out of scope for the M4 frontend slice).
 * The endpoint shape is documented in `SpendSummary` below.
 */

export interface SpendMissionEntry {
  /** Stable mission identifier — used as React key. */
  id: string;
  /** Display label (mission title or generated name). */
  name: string;
  /** USD spend attributed to this mission for the period. */
  amount_usd: number;
}

export interface SpendSummary {
  /** Month-to-date USD spend across compute + LLM. */
  mtd_spend_usd: number;
  /** Plan cap for the same period (compute + LLM combined). */
  plan_cap_usd: number;
  /** Sub-component spend, surfaced as informational chips. */
  components?: {
    llm_usd?: number;
    compute_usd?: number;
  };
  /** Top mission contributors sorted desc by amount. */
  top_missions?: SpendMissionEntry[];
}

export interface SpendDashboardProps {
  /**
   * Optional initial data — when provided, the component renders
   * synchronously without a fetch. Used by tests + by parent pages
   * that have already loaded the data.
   */
  initialSummary?: SpendSummary;
  /** Override the fetch endpoint. Defaults to `/governance/spend`. */
  endpoint?: string;
  /** Hide the refresh button (useful in embedded contexts). */
  hideRefresh?: boolean;
}

const ALERT_THRESHOLD_PCT = 90;

const formatUsd = (value: number): string => {
  const safe = Number.isFinite(value) ? value : 0;
  return safe.toLocaleString('en-US', {
    style: 'currency',
    currency: 'USD',
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
};

const computeUtilizationPct = (spend: number, cap: number): number => {
  if (!cap || cap <= 0) return 0;
  const pct = (spend / cap) * 100;
  if (!Number.isFinite(pct) || pct < 0) return 0;
  return Math.min(100, pct);
};

const gaugeColorClass = (utilizationPct: number): string => {
  if (utilizationPct >= 100) return 'bg-theme-error-bg';
  if (utilizationPct >= ALERT_THRESHOLD_PCT) return 'bg-theme-warning-bg';
  return 'bg-theme-success-bg';
};

export const SpendDashboard: React.FC<SpendDashboardProps> = ({
  initialSummary,
  endpoint = '/governance/spend',
  hideRefresh = false,
}) => {
  const [summary, setSummary] = useState<SpendSummary | null>(initialSummary ?? null);
  const [loading, setLoading] = useState<boolean>(!initialSummary);
  const [refreshing, setRefreshing] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);

  const loadSummary = useCallback(
    async (isRefresh = false) => {
      if (isRefresh) setRefreshing(true);
      else setLoading(true);
      setError(null);
      try {
        const data = await governanceSpendApi.getSpendSummary(endpoint);
        setSummary(data);
      } catch (err) {
        logger.error('SpendDashboard fetch failed', { error: err });
        setError('Unable to load spend summary');
      } finally {
        setLoading(false);
        setRefreshing(false);
      }
    },
    [endpoint],
  );

  useEffect(() => {
    if (!initialSummary) {
      loadSummary(false);
    }
    // We intentionally only run on mount when no initial data was provided.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const utilizationPct = useMemo(
    () => computeUtilizationPct(summary?.mtd_spend_usd ?? 0, summary?.plan_cap_usd ?? 0),
    [summary?.mtd_spend_usd, summary?.plan_cap_usd],
  );

  const remaining = useMemo(() => {
    if (!summary) return 0;
    return Math.max(0, (summary.plan_cap_usd ?? 0) - (summary.mtd_spend_usd ?? 0));
  }, [summary]);

  const overCap = useMemo(
    () => summary != null && (summary.mtd_spend_usd ?? 0) > (summary.plan_cap_usd ?? 0),
    [summary],
  );

  const nearCap = useMemo(
    () => !overCap && utilizationPct >= ALERT_THRESHOLD_PCT,
    [overCap, utilizationPct],
  );

  if (loading) {
    return (
      <div className="space-y-4" data-testid="spend-dashboard-loading">
        <div className="animate-pulse space-y-3">
          <div className="h-8 bg-theme-surface rounded" />
          <div className="h-24 bg-theme-surface rounded" />
          <div className="h-32 bg-theme-surface rounded" />
        </div>
      </div>
    );
  }

  if (error || !summary) {
    return (
      <div
        className="bg-theme-surface border border-theme-error-border rounded-lg p-6"
        data-testid="spend-dashboard-error"
      >
        <div className="flex items-center gap-2 text-theme-error-fg">
          <AlertTriangle className="w-5 h-5" />
          <p className="font-medium">{error ?? 'No spend data available'}</p>
        </div>
        {!hideRefresh && (
          <button
            type="button"
            onClick={() => loadSummary(true)}
            className="mt-4 inline-flex items-center gap-2 px-3 py-1.5 rounded-md bg-theme-interactive-secondary text-theme-primary text-sm"
            data-testid="spend-dashboard-retry"
          >
            <RefreshCw className="w-4 h-4" />
            Retry
          </button>
        )}
      </div>
    );
  }

  const topMissions = summary.top_missions ?? [];
  const llmComponent = summary.components?.llm_usd;
  const computeComponent = summary.components?.compute_usd;

  return (
    <div className="space-y-6" data-testid="spend-dashboard">
      {/* Header + refresh */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-xl font-semibold text-theme-primary flex items-center gap-2">
            <TrendingUp className="w-5 h-5" aria-hidden="true" />
            Month-to-Date Spend
          </h2>
          <p className="text-sm text-theme-secondary mt-1">
            Combined compute + LLM spend against the current plan cap.
          </p>
        </div>
        {!hideRefresh && (
          <button
            type="button"
            onClick={() => loadSummary(true)}
            disabled={refreshing}
            className="inline-flex items-center gap-2 px-3 py-1.5 rounded-md bg-theme-interactive-secondary text-theme-primary text-sm disabled:opacity-50"
            data-testid="spend-dashboard-refresh"
          >
            <RefreshCw className={`w-4 h-4 ${refreshing ? 'animate-spin' : ''}`} />
            Refresh
          </button>
        )}
      </div>

      {/* Gauge */}
      <div
        className="bg-theme-surface border border-theme-light rounded-lg p-6"
        data-testid="spend-gauge"
      >
        <div className="flex items-baseline justify-between mb-3">
          <div>
            <p
              className="text-3xl font-semibold text-theme-primary"
              data-testid="spend-mtd"
            >
              {formatUsd(summary.mtd_spend_usd)}
            </p>
            <p className="text-sm text-theme-secondary">
              of <span data-testid="spend-cap">{formatUsd(summary.plan_cap_usd)}</span> plan
              cap
            </p>
          </div>
          <div className="text-right">
            <p
              className="text-sm text-theme-secondary"
              data-testid="spend-utilization-label"
            >
              {utilizationPct.toFixed(1)}% used
            </p>
            <p className="text-sm text-theme-tertiary" data-testid="spend-remaining">
              {formatUsd(remaining)} remaining
            </p>
          </div>
        </div>

        {/* Gauge bar */}
        <div
          className="h-3 w-full bg-theme-background-secondary rounded-full overflow-hidden"
          role="progressbar"
          aria-valuenow={Math.round(utilizationPct)}
          aria-valuemin={0}
          aria-valuemax={100}
          data-testid="spend-gauge-bar"
        >
          <div
            className={`h-full ${gaugeColorClass(utilizationPct)} transition-all`}
            style={{ width: `${utilizationPct}%` }}
          />
        </div>

        {/* Alert chips */}
        <div className="mt-4 flex flex-wrap gap-2">
          {overCap && (
            <span
              className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-medium bg-theme-error-bg text-theme-primary"
              data-testid="spend-alert-over"
            >
              <AlertTriangle className="w-3 h-3" />
              Over plan cap
            </span>
          )}
          {nearCap && (
            <span
              className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-medium bg-theme-warning-bg text-theme-primary"
              data-testid="spend-alert-near"
            >
              <AlertTriangle className="w-3 h-3" />
              Approaching plan cap
            </span>
          )}
          {typeof llmComponent === 'number' && (
            <span
              className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-medium bg-theme-info-bg text-theme-primary"
              data-testid="spend-component-llm"
            >
              LLM {formatUsd(llmComponent)}
            </span>
          )}
          {typeof computeComponent === 'number' && (
            <span
              className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-medium bg-theme-info-bg text-theme-primary"
              data-testid="spend-component-compute"
            >
              Compute {formatUsd(computeComponent)}
            </span>
          )}
        </div>
      </div>

      {/* Per-mission breakdown */}
      <div
        className="bg-theme-surface border border-theme-light rounded-lg"
        data-testid="spend-breakdown"
      >
        <div className="px-6 py-4 border-b border-theme-light">
          <h3 className="text-base font-semibold text-theme-primary">
            Top missions by spend
          </h3>
          <p className="text-xs text-theme-tertiary mt-1">
            Five highest contributors to MTD spend.
          </p>
        </div>
        {topMissions.length === 0 ? (
          <div
            className="px-6 py-8 text-center text-theme-secondary text-sm"
            data-testid="spend-breakdown-empty"
          >
            No mission spend recorded for this period.
          </div>
        ) : (
          <ul className="divide-y divide-theme">
            {topMissions.slice(0, 5).map((mission) => (
              <li
                key={mission.id}
                className="px-6 py-3 flex items-center justify-between"
                data-testid={`spend-mission-${mission.id}`}
              >
                <span className="text-sm text-theme-primary truncate pr-4">
                  <EntityLink type="mission" id={mission.id} label={mission.name} />
                </span>
                <span className="text-sm font-medium text-theme-primary tabular-nums">
                  {formatUsd(mission.amount_usd)}
                </span>
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  );
};

export default SpendDashboard;

import React, { useState, useEffect, useRef } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { Activity } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Select } from '@/shared/components/ui/Select';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useRefreshAction } from '@/shared/hooks/useRefreshAction';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';
import type { RealTimeMetrics } from '@/shared/services/ai/AiOpsApiService';
import { AIOPS_KEYS, useAiOpsDashboard, useAiOpsRealTime } from '../api/aiopsApi';
import { formatNumber, formatDuration, formatPercent, getHealthBadge } from './aiopsHelpers';
import { AiOpsTimeRange } from './sections/sectionShared';
import { OverviewSection } from './sections/OverviewSection';
import { TrendsSection } from './sections/TrendsSection';
import { ProvidersSection } from './sections/ProvidersSection';
import { AgentsSection } from './sections/AgentsSection';

const TIME_RANGE_OPTIONS = [
  { value: '5m', label: 'Last 5 minutes' },
  { value: '15m', label: 'Last 15 minutes' },
  { value: '30m', label: 'Last 30 minutes' },
  { value: '1h', label: 'Last 1 hour' },
  { value: '6h', label: 'Last 6 hours' },
  { value: '24h', label: 'Last 24 hours' },
  { value: '7d', label: 'Last 7 days' },
];

/** Compact real-time stat shown in the Operations controls bar ticker. */
const TickerStat: React.FC<{ label: string; value: string; emphasis?: boolean }> = ({ label, value, emphasis }) => (
  <div className="text-center px-3">
    <p className="text-[10px] text-theme-tertiary uppercase tracking-wide">{label}</p>
    <p className={`text-sm font-bold ${emphasis ? 'text-theme-error-fg' : 'text-theme-primary'}`}>{value}</p>
  </div>
);

const LiveTicker: React.FC<{ realTime: RealTimeMetrics }> = ({ realTime }) => {
  const errorRate = realTime?.current_error_rate ?? 0;
  return (
    <div className="flex flex-wrap items-center divide-x divide-theme bg-theme-surface border border-theme rounded-lg py-2">
      <TickerStat label="Req/sec" value={formatNumber(Number((realTime?.current_requests_per_second ?? 0).toFixed(1)))} />
      <TickerStat label="Avg Latency" value={formatDuration(realTime?.current_avg_latency_ms)} />
      <TickerStat label="Error Rate" value={formatPercent(errorRate, true)} emphasis={errorRate > 0.05} />
      <TickerStat label="Queue" value={formatNumber(realTime?.queue_depth ?? 0)} />
      <TickerStat label="Connections" value={formatNumber(realTime?.active_connections ?? 0)} />
    </div>
  );
};

/**
 * Embeddable AIOps Operations-tab body.
 *
 * Owns a compact controls bar (time-range Select + live ticker + health badge)
 * whose time range drives its four operational sections, rendered as a FLAT
 * vertical stack — no inner tabs. Each section is standalone and self-fetches via
 * the shared react-query hooks (deduped by query key), so changing the range
 * triggers a single refetch shared across the header and all sections.
 *
 * Cost and Reliability are NOT rendered here — they are exported for mounting
 * into the Observability Credits/Alerts tabs. The one-shot dashboard-error toast
 * lives only here (distributed sections show inline error+retry, no toast, since
 * they share one query and per-section toasts would spam).
 *
 * Mounted at `AIMonitoringPage` (Operations tab); keep it exported + prop-less.
 */
export const AiOpsContent: React.FC = () => {
  const [timeRange, setTimeRange] = useState<AiOpsTimeRange>('1h');
  const { addNotification } = useNotifications();

  const dashboardQuery = useAiOpsDashboard(timeRange);
  const realTimeQuery = useAiOpsRealTime();

  // Refetch the operational surface on relevant websocket pushes (header + all
  // sections update because they share the dashboard query).
  usePageWebSocket({
    pageType: 'ai',
    onDataUpdate: () => {
      dashboardQuery.refetch();
      realTimeQuery.refetch();
    },
  });

  // One-shot error toast, gated on the isError transition so it fires once per failure.
  const errorNotified = useRef(false);
  useEffect(() => {
    if (dashboardQuery.isError && !errorNotified.current) {
      errorNotified.current = true;
      addNotification({
        type: 'error',
        title: 'AIOps',
        message: 'Failed to load operations data. Please try again.',
      });
    }
    if (!dashboardQuery.isError) {
      errorNotified.current = false;
    }
  }, [dashboardQuery.isError, addNotification]);

  const realTime = realTimeQuery.data ?? dashboardQuery.data?.real_time;

  return (
    <div className="space-y-6">
      {/* Compact controls bar */}
      <div className="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-3">
        <div className="flex items-center gap-3">
          <Select
            value={timeRange}
            onValueChange={(value) => setTimeRange(value as AiOpsTimeRange)}
            options={TIME_RANGE_OPTIONS}
            fullWidth={false}
            className="w-44"
            aria-label="Time range"
          />
          <span className="flex items-center gap-1.5 text-sm text-theme-secondary">
            <Activity className="h-4 w-4" />
            Health
          </span>
          {getHealthBadge(dashboardQuery.data?.health?.status)}
        </div>
        {realTime && <LiveTicker realTime={realTime} />}
      </div>

      {/* Flat stack of operational sections (time-range driven) */}
      <OverviewSection timeRange={timeRange} />
      <TrendsSection timeRange={timeRange} />
      <ProvidersSection timeRange={timeRange} />
      <AgentsSection timeRange={timeRange} />
    </div>
  );
};

/**
 * Thin standalone page wrapper (not part of the distributed Observability tabs,
 * retained for direct/standalone use). Owns the page chrome + a refresh action
 * that invalidates the AIOps query keys; the self-fetching sections refetch.
 */
export const AiOpsDashboard: React.FC = () => {
  const queryClient = useQueryClient();
  const { refreshAction } = useRefreshAction({
    onRefresh: () => {
      queryClient.invalidateQueries({ queryKey: AIOPS_KEYS.all });
    },
  });

  return (
    <PageContainer
      title="AI Operations"
      description="Real-time monitoring and observability for AI workloads"
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'AI', href: '/app/ai' },
        { label: 'AIOps' },
      ]}
      actions={[refreshAction]}
    >
      <AiOpsContent />
    </PageContainer>
  );
};

export default AiOpsDashboard;

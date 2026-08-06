// Mission-control landing surface for the core app.
//
// Replaces the old starter-template overview (hardcoded "Account created"
// checklist + static "Platform Ready" banner) with a live posture read of the
// fleet: what is waiting on a human (approvals), what is running (missions),
// what it is costing (budget regime) and how much rope the agents have (trust
// tiers). Every panel binds to an API that already exists — no new endpoints.
//
// Failure policy: every fetch fails soft. A rejected query renders an em-dash
// placeholder or an empty state, never an error page — the landing screen must
// stay usable when one subsystem is down.
//
// Permission policy: governance and mission panels are mounted only when the
// user holds the permission the backing controller requires
// (`ai.agents.read` for autonomy, `ai.missions.read` for missions), so we never
// fire a request the user cannot make. Permissions only — never roles.
import React, { useCallback, useEffect, useMemo } from 'react';
import { useNavigate } from 'react-router-dom';
import { useSelector } from 'react-redux';
import { useQueryClient } from '@tanstack/react-query';
import {
  Activity,
  ArrowRight,
  BarChart3,
  Bot,
  ClipboardCheck,
  Coins,
  Gauge,
  Package,
  Rocket,
  Route as RouteIcon,
  ShieldCheck,
  Users,
  Wallet,
  Zap,
} from 'lucide-react';
import type { LucideIcon } from 'lucide-react';
import { RootState } from '@/shared/services';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { Badge } from '@/shared/components/ui/Badge';
import { ChartFrame, MeterBar, Sparkline, StatTile } from '@/shared/components/charts';
import type { ChartTone } from '@/shared/components/charts';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';
import { useDashboardStats } from '@/shared/hooks/useDashboardStats';
import { DashboardAIOverview } from '@/features/ai/monitoring/components/DashboardAIOverview';
import { BudgetRegimeIndicator } from '@/features/ai/autonomy/components/BudgetRegimeIndicator';
import { useApprovalQueue, useAutonomyStats } from '@/features/ai/autonomy/api/autonomyApi';
import type { AutonomyStats, BudgetRegime } from '@/features/ai/autonomy/types/autonomy';
import { useMissions } from '@/features/missions';
import type { Mission } from '@/features/missions';

// --- Route contract -------------------------------------------------------
// Every path below is copied from the routes block in `DashboardPage.tsx`.
// `/app/ai/agents/autonomy` is the deepest addressable autonomy entry point:
// the autonomy sidebar (approvals, budgets, trust, kill switch) is component
// state, not URL state, so a section cannot be linked directly today.
const PATHS = {
  agents: '/app/ai/agents',
  autonomy: '/app/ai/agents/autonomy',
  approvalChains: '/app/ai/approval-chains',
  governance: '/app/ai/governance',
  missions: '/app/ai/missions',
  modelRouter: '/app/ai/infrastructure/model-router',
  cost: '/app/ai/cost',
  observability: '/app/ai/observability',
  operations: '/app/ai/operations',
  sourceControl: '/app/devops/source-control',
  devops: '/app/devops',
  aiOverview: '/app/ai',
} as const;

const PLACEHOLDER = '—';

/** React Query root key used by `autonomyApi` (`AUTONOMY_KEYS.all`). */
const AUTONOMY_QUERY_ROOT = ['autonomy'];

const MISSION_TREND_DAYS = 7;
const DAY_MS = 86_400_000;

type ChipTone = 'default' | 'success' | 'warning' | 'danger' | 'info';

interface StatusChipProps {
  icon: LucideIcon;
  label: string;
  value: React.ReactNode;
  tone?: ChipTone;
  onClick: () => void;
}

/** Compact posture pill. Carries one number and its tone; always clickable. */
const StatusChip: React.FC<StatusChipProps> = ({ icon: Icon, label, value, tone = 'default', onClick }) => (
  <button
    type="button"
    onClick={onClick}
    className="flex items-center gap-2 rounded-full border border-theme bg-theme-surface px-3 py-1.5 text-xs transition-colors hover:bg-theme-surface-hover"
  >
    <Icon className="h-3.5 w-3.5 shrink-0 text-theme-tertiary" />
    <span className="text-theme-secondary">{label}</span>
    <Badge variant={tone} size="xs">{value}</Badge>
  </button>
);

// --- Derivations ----------------------------------------------------------

const EMPTY_AUTONOMY_STATS: AutonomyStats = {
  total_agents: 0,
  supervised: 0,
  monitored: 0,
  trusted: 0,
  autonomous: 0,
  pending_promotions: 0,
  pending_demotions: 0,
};

/**
 * Budget regime from aggregate spend. Thresholds mirror
 * `AutonomyDashboardPage.computeBudgetRegime` — the autonomy dashboard is the
 * source of truth; keep the two in step if the bands move.
 */
function computeBudgetRegime(stats: AutonomyStats): BudgetRegime | null {
  const budgets = stats.budgets;
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

const REGIME_TONE: Record<BudgetRegime['level'], { chip: ChipTone; chart: ChartTone }> = {
  NORMAL: { chip: 'success', chart: 'success' },
  CAUTIOUS: { chip: 'info', chart: 'info' },
  CRITICAL: { chip: 'warning', chart: 'warning' },
  EXHAUSTED: { chip: 'danger', chart: 'error' },
};

const formatCents = (cents: number): string =>
  `$${(cents / 100).toLocaleString(undefined, { maximumFractionDigits: 2 })}`;

/**
 * Autonomy snapshot shared by the chip row, the tiles and the charts.
 *
 * All three call this; React Query de-duplicates by query key, so the extra
 * call sites cost nothing on the wire and each block stays independently
 * permission-gated.
 */
function useGovernanceSnapshot() {
  const { data: rawStats, isLoading: statsLoading, isError: statsError } = useAutonomyStats();
  const { data: approvals, isLoading: approvalsLoading, isError: approvalsError } = useApprovalQueue();

  const stats = rawStats ?? EMPTY_AUTONOMY_STATS;
  const pendingApprovals = (approvals ?? []).filter((request) => request.status === 'pending').length;

  return {
    stats,
    regime: computeBudgetRegime(stats),
    pendingApprovals,
    // A failed fetch is indistinguishable from "no data" for display purposes:
    // both render the placeholder rather than a zero we cannot vouch for.
    statsUnavailable: statsLoading || statsError || !rawStats,
    approvalsUnavailable: approvalsLoading || approvalsError || !approvals,
  };
}

/** Missions created per day over the trailing week, oldest → newest. */
function missionTrend(missions: Mission[]): number[] {
  const buckets = new Array<number>(MISSION_TREND_DAYS).fill(0);
  const today = new Date();
  today.setHours(0, 0, 0, 0);

  missions.forEach((mission) => {
    const created = new Date(mission.created_at);
    if (Number.isNaN(created.getTime())) return;
    created.setHours(0, 0, 0, 0);
    const daysAgo = Math.round((today.getTime() - created.getTime()) / DAY_MS);
    if (daysAgo >= 0 && daysAgo < MISSION_TREND_DAYS) {
      buckets[MISSION_TREND_DAYS - 1 - daysAgo] += 1;
    }
  });

  return buckets;
}

// --- Governance blocks (mounted only with `ai.agents.read`) ----------------

const GovernanceChips: React.FC<{ onNavigate: (path: string) => void }> = ({ onNavigate }) => {
  const { stats, regime, pendingApprovals, statsUnavailable, approvalsUnavailable } = useGovernanceSnapshot();

  return (
    <>
      <StatusChip
        icon={ClipboardCheck}
        label="Approvals waiting"
        value={approvalsUnavailable ? PLACEHOLDER : pendingApprovals}
        tone={!approvalsUnavailable && pendingApprovals > 0 ? 'warning' : 'default'}
        onClick={() => onNavigate(PATHS.autonomy)}
      />
      <StatusChip
        icon={Wallet}
        label="Budget"
        value={regime ? `${regime.level.toLowerCase()} · ${regime.utilization_pct.toFixed(0)}%` : PLACEHOLDER}
        tone={regime ? REGIME_TONE[regime.level].chip : 'default'}
        onClick={() => onNavigate(PATHS.cost)}
      />
      <StatusChip
        icon={ShieldCheck}
        label="Trusted / autonomous"
        value={statsUnavailable ? PLACEHOLDER : `${stats.trusted + stats.autonomous} of ${stats.total_agents}`}
        tone="info"
        onClick={() => onNavigate(PATHS.autonomy)}
      />
      <StatusChip
        icon={Gauge}
        label="Tier changes pending"
        value={statsUnavailable ? PLACEHOLDER : stats.pending_promotions + stats.pending_demotions}
        tone={!statsUnavailable && stats.pending_promotions + stats.pending_demotions > 0 ? 'info' : 'default'}
        onClick={() => onNavigate(PATHS.autonomy)}
      />
    </>
  );
};

/** Fragment of tiles — rendered straight into the parent tile grid. */
const GovernanceTiles: React.FC<{ onNavigate: (path: string) => void }> = ({ onNavigate }) => {
  const { stats, regime, pendingApprovals, statsUnavailable, approvalsUnavailable } = useGovernanceSnapshot();
  const budgets = stats.budgets;

  return (
    <>
      <StatTile
        label="Approvals waiting"
        value={approvalsUnavailable ? PLACEHOLDER : pendingApprovals}
        icon={<ClipboardCheck className="h-4 w-4 text-theme-tertiary" />}
        sub={
          approvalsUnavailable
            ? 'Approval queue unavailable'
            : pendingApprovals > 0
              ? 'Agents are blocked on a human decision'
              : 'Nothing blocked on a human'
        }
        onClick={() => onNavigate(PATHS.autonomy)}
      />

      <StatTile
        label="Budget used"
        value={regime ? `${regime.utilization_pct.toFixed(0)}%` : PLACEHOLDER}
        icon={<Coins className="h-4 w-4 text-theme-tertiary" />}
        sub={
          budgets && regime
            ? `${formatCents(budgets.total_spent_cents)} of ${formatCents(budgets.total_budget_cents)} · ${budgets.exceeded} exceeded`
            : statsUnavailable
              ? 'Budget data unavailable'
              : 'No agent budgets configured'
        }
        onClick={() => onNavigate(PATHS.cost)}
      >
        {budgets && regime && (
          <MeterBar
            value={budgets.total_spent_cents}
            max={budgets.total_budget_cents}
            capMarker={0.8}
            tone={REGIME_TONE[regime.level].chart}
            ariaLabel="Agent budget spent against allocation"
          />
        )}
      </StatTile>
    </>
  );
};

const TIER_ROWS: Array<{ key: keyof Pick<AutonomyStats, 'supervised' | 'monitored' | 'trusted' | 'autonomous'>; label: string; tone: ChartTone }> = [
  { key: 'supervised', label: 'Supervised', tone: 'warning' },
  { key: 'monitored', label: 'Monitored', tone: 'info' },
  { key: 'trusted', label: 'Trusted', tone: 'success' },
  { key: 'autonomous', label: 'Autonomous', tone: 'primary' },
];

const GovernanceCharts: React.FC = () => {
  const { stats, regime, statsUnavailable } = useGovernanceSnapshot();

  return (
    <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
      <ChartFrame
        title="Agents by trust tier"
        subtitle="How much rope each agent has today"
        height={180}
      >
        {statsUnavailable || stats.total_agents === 0 ? (
          <p className="flex h-full items-center justify-center text-sm text-theme-tertiary">
            {statsUnavailable ? 'Trust data unavailable' : 'No agents evaluated yet'}
          </p>
        ) : (
          <div className="flex h-full flex-col justify-center gap-3">
            {TIER_ROWS.map((row) => (
              <div key={row.key} className="space-y-1">
                <div className="flex items-baseline justify-between text-xs">
                  <span className="text-theme-secondary">{row.label}</span>
                  <span className="text-theme-primary font-medium">{stats[row.key]}</span>
                </div>
                <MeterBar
                  value={stats[row.key]}
                  max={stats.total_agents}
                  tone={row.tone}
                  ariaLabel={`${row.label} agents out of ${stats.total_agents}`}
                />
              </div>
            ))}
          </div>
        )}
      </ChartFrame>

      <ChartFrame
        title="Budget regime"
        subtitle="Aggregate agent spend against allocation"
        height={180}
      >
        {regime ? (
          <div className="flex h-full flex-col justify-center gap-3">
            <BudgetRegimeIndicator regime={regime} />
            <p className="text-xs text-theme-tertiary">
              {formatCents(regime.remaining_cents)} remaining
            </p>
          </div>
        ) : (
          <p className="flex h-full items-center justify-center text-sm text-theme-tertiary">
            {statsUnavailable ? 'Budget data unavailable' : 'No agent budgets configured'}
          </p>
        )}
      </ChartFrame>
    </div>
  );
};

// --- Quick links ----------------------------------------------------------

interface QuickLink {
  id: string;
  label: string;
  description: string;
  icon: LucideIcon;
  path: string;
  visible: boolean;
}

const QuickLinks: React.FC<{ links: QuickLink[]; onNavigate: (path: string) => void }> = ({ links, onNavigate }) => (
  <div className="card-theme-elevated p-6">
    <h3 className="text-xl font-semibold text-theme-primary mb-4">Jump to</h3>
    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
      {links.map((link) => {
        const Icon = link.icon;
        return (
          <button
            key={link.id}
            type="button"
            onClick={() => onNavigate(link.path)}
            className="flex w-full items-center justify-between gap-3 rounded-lg border border-theme bg-theme-surface p-4 text-left transition-colors hover:bg-theme-surface-hover"
          >
            <span className="flex min-w-0 items-center gap-3">
              <Icon className="h-5 w-5 shrink-0 text-theme-tertiary" />
              <span className="min-w-0">
                <span className="block truncate text-sm font-medium text-theme-primary">{link.label}</span>
                <span className="block truncate text-xs text-theme-tertiary">{link.description}</span>
              </span>
            </span>
            <ArrowRight className="h-4 w-4 shrink-0 text-theme-tertiary" />
          </button>
        );
      })}
    </div>
  </div>
);

// --- Page -----------------------------------------------------------------

export const DashboardOverview: React.FC = () => {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const { user } = useSelector((state: RootState) => state.auth);
  const { stats, loading: statsLoading, refresh: refreshStats } = useDashboardStats();

  // Permissions only — never roles.
  const canReadAgents = user?.permissions?.includes('ai.agents.read') ?? false;
  const canReadMissions = user?.permissions?.includes('ai.missions.read') ?? false;
  const canManageChains = user?.permissions?.includes('ai.approval_chains.manage') ?? false;

  const { missions, loading: missionsLoading, error: missionsError, fetchMissions } = useMissions();

  useEffect(() => {
    if (canReadMissions) fetchMissions();
  }, [canReadMissions, fetchMissions]);

  // Handle websocket data updates
  const handleDataUpdate = useCallback(() => {
    refreshStats();
    if (canReadMissions) fetchMissions();
    if (canReadAgents) queryClient.invalidateQueries({ queryKey: AUTONOMY_QUERY_ROOT });
  }, [refreshStats, fetchMissions, queryClient, canReadMissions, canReadAgents]);

  // WebSocket connection for real-time dashboard updates
  usePageWebSocket({
    pageType: 'dashboard',
    onDataUpdate: handleDataUpdate,
    onNotification: handleDataUpdate
  });

  const activeMissions = useMemo(
    () => missions.filter((mission) => mission.status === 'active').length,
    [missions]
  );
  const missionSeries = useMemo(() => missionTrend(missions), [missions]);
  const hasRecentMissions = missionSeries.some((count) => count > 0);
  const missionsUnavailable = missionsLoading || !!missionsError;

  const healthTone: ChartTone =
    stats.systemHealth.status === 'healthy' ? 'success' : stats.systemHealth.status === 'degraded' ? 'warning' : 'error';

  const quickLinks: QuickLink[] = [
    {
      id: 'autonomy',
      label: 'Autonomy',
      description: 'Approvals, trust, budgets, kill switch',
      icon: ShieldCheck,
      path: PATHS.autonomy,
      visible: canReadAgents,
    },
    {
      id: 'approval-chains',
      label: 'Approval chains',
      description: 'Multi-step workflows for high-risk actions',
      icon: RouteIcon,
      path: PATHS.approvalChains,
      visible: canManageChains,
    },
    {
      id: 'governance',
      label: 'Governance',
      description: 'Audit trail, security posture, policy',
      icon: Activity,
      path: PATHS.governance,
      visible: true,
    },
    {
      id: 'model-router',
      label: 'Model router',
      description: 'Routing rules, escalations, model catalog',
      icon: RouteIcon,
      path: PATHS.modelRouter,
      visible: true,
    },
    {
      id: 'missions',
      label: 'Missions',
      description: 'Objectives in flight and their task graphs',
      icon: Rocket,
      path: PATHS.missions,
      visible: canReadMissions,
    },
    {
      id: 'operations',
      label: 'Operations',
      description: 'Alerts, incidents, execution traces',
      icon: Zap,
      path: PATHS.operations,
      visible: true,
    },
  ].filter((link) => link.visible);

  const pageActions: PageAction[] = [
    {
      id: 'ai-overview',
      label: 'AI Overview',
      onClick: () => navigate(PATHS.aiOverview),
      variant: 'secondary',
      icon: BarChart3
    },
    ...(canReadMissions
      ? [{
          id: 'missions',
          label: 'Missions',
          onClick: () => navigate(PATHS.missions),
          variant: 'secondary' as const,
          icon: Rocket
        }]
      : []),
    {
      id: 'devops',
      label: 'DevOps',
      onClick: () => navigate(PATHS.devops),
      variant: 'secondary',
      icon: Users
    }
  ];

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'Mission Control' }
  ];

  return (
    <PageContainer
      title="Mission Control"
      description={`Live fleet posture for ${user?.name || 'your account'} — what is waiting on you, what is running, and what it is costing.`}
      breadcrumbs={breadcrumbs}
      actions={pageActions}
    >
      <div className="space-y-6">
        {/* Posture chips — one line, one number each, all deep-linked */}
        <div className="flex flex-wrap items-center gap-2">
          <StatusChip
            icon={Activity}
            label="System health"
            value={statsLoading ? PLACEHOLDER : `${stats.systemHealth.score}%`}
            tone={stats.systemHealth.status === 'healthy' ? 'success' : stats.systemHealth.status === 'degraded' ? 'warning' : 'danger'}
            onClick={() => navigate(PATHS.observability)}
          />
          <StatusChip
            icon={Bot}
            label="Agents active"
            value={statsLoading ? PLACEHOLDER : `${stats.agents.active} of ${stats.agents.total}`}
            tone={stats.agents.errored > 0 ? 'warning' : 'default'}
            onClick={() => navigate(PATHS.agents)}
          />
          {canReadMissions && (
            <StatusChip
              icon={Rocket}
              label="Missions running"
              value={missionsUnavailable ? PLACEHOLDER : activeMissions}
              tone={activeMissions > 0 ? 'info' : 'default'}
              onClick={() => navigate(PATHS.missions)}
            />
          )}
          {canReadAgents && <GovernanceChips onNavigate={navigate} />}
        </div>

        {/* Headline figures */}
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
          <StatTile
            label="System health"
            value={statsLoading ? PLACEHOLDER : stats.systemHealth.score}
            unit={statsLoading ? undefined : '%'}
            icon={<Activity className="h-4 w-4 text-theme-tertiary" />}
            sub={statsLoading ? 'Loading…' : stats.systemHealth.status === 'healthy' ? 'All systems operational' : `Status: ${stats.systemHealth.status}`}
            onClick={() => navigate(PATHS.observability)}
          >
            {!statsLoading && (
              <MeterBar
                value={stats.systemHealth.score}
                max={100}
                tone={healthTone}
                ariaLabel="System health score"
              />
            )}
          </StatTile>

          <StatTile
            label="AI agents"
            value={statsLoading ? PLACEHOLDER : stats.agents.total}
            icon={<Bot className="h-4 w-4 text-theme-tertiary" />}
            sub={
              statsLoading
                ? 'Loading…'
                : `${stats.agents.active} active · ${stats.agents.paused} paused · ${stats.agents.errored} errored`
            }
            onClick={() => navigate(PATHS.agents)}
          />

          <StatTile
            label="Repositories"
            value={statsLoading ? PLACEHOLDER : stats.repositories}
            icon={<Package className="h-4 w-4 text-theme-tertiary" />}
            sub={statsLoading ? 'Loading…' : stats.repositories > 0 ? 'Connected to source control' : 'Connect your repos'}
            onClick={() => navigate(PATHS.sourceControl)}
          />

          <StatTile
            label="Executions today"
            value={statsLoading ? PLACEHOLDER : stats.overview.totalExecutionsToday}
            icon={<Zap className="h-4 w-4 text-theme-tertiary" />}
            sub={
              statsLoading
                ? 'Loading…'
                : stats.overview.totalExecutionsToday > 0
                  ? `${stats.overview.successRate.toFixed(1)}% success · ${stats.overview.avgResponseTime.toFixed(0)}ms avg`
                  : 'No executions yet'
            }
            onClick={() => navigate(PATHS.observability)}
          >
            {!statsLoading && stats.overview.totalExecutionsToday > 0 && (
              <MeterBar
                value={stats.overview.successRate}
                max={100}
                tone={stats.overview.successRate >= 90 ? 'success' : stats.overview.successRate >= 70 ? 'warning' : 'error'}
                ariaLabel="Execution success rate today"
              />
            )}
          </StatTile>

          {canReadAgents && <GovernanceTiles onNavigate={navigate} />}

          {canReadMissions && (
            <StatTile
              label="Missions running"
              value={missionsUnavailable ? PLACEHOLDER : activeMissions}
              icon={<Rocket className="h-4 w-4 text-theme-tertiary" />}
              sub={
                missionsUnavailable
                  ? 'Mission data unavailable'
                  : hasRecentMissions
                    ? `${missions.length} total · started per day, last ${MISSION_TREND_DAYS} days`
                    : `${missions.length} total · none started this week`
              }
              onClick={() => navigate(PATHS.missions)}
            >
              {/* Only drawn when the week actually has activity — a flat line
                  through an all-zero series reads as a steady non-zero rate. */}
              {!missionsUnavailable && hasRecentMissions && (
                <Sparkline
                  data={missionSeries}
                  tone="info"
                  ariaLabel={`Missions created per day over the last ${MISSION_TREND_DAYS} days`}
                />
              )}
            </StatTile>
          )}
        </div>

        {canReadAgents && <GovernanceCharts />}

        {/* AI Platform Overview */}
        <DashboardAIOverview stats={stats} loading={statsLoading} />

        <QuickLinks links={quickLinks} onNavigate={navigate} />
      </div>
    </PageContainer>
  );
};

export default DashboardOverview;

import React from 'react';
import { HeartPulse, Server, MessageSquare, ClipboardCheck, Bell, Zap, Workflow } from 'lucide-react';
import type { PathTabSpec } from '@/shared/components/navigation/PathTabs';

/**
 * Get color class for health score
 */
export const getHealthScoreColor = (score: number): string => {
  if (score >= 80) return 'text-theme-success-fg';
  if (score >= 50) return 'text-theme-warning-fg';
  return 'text-theme-error-fg';
};

/**
 * Get background class for connection status
 */
export const getConnectionStatusColor = (isConnected: boolean): string => {
  return isConnected ? 'bg-theme-success-bg' : 'bg-theme-error-bg';
};

/**
 * Format relative time for last update display
 */
export const formatLastUpdate = (date: Date | null): string => {
  if (!date) return 'Never';
  const now = new Date();
  const diff = now.getTime() - date.getTime();
  const seconds = Math.floor(diff / 1000);

  if (seconds < 60) return `${seconds}s ago`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  return `${hours}h ago`;
};

/**
 * Path-based tab identifiers for the Observability hub (`/app/ai/observability`).
 */
export type MonitoringTabId =
  | 'systems'
  | 'circuit-breakers'
  | 'alerts'
  | 'self-healing'
  | 'conversations'
  | 'traces'
  | 'evaluation';

/**
 * Tab definitions for the Observability hub — consumed directly by the canonical
 * `PathTabs` scaffold (one URL segment per tab).
 *
 * fc-42: Observability and the former Operations hub (AIOps/Alerts/Execution
 * Traces) are ONE page now — a frontend-consolidation audit found the two
 * backends (Monitoring::UnifiedService and Ai::Analytics::DashboardService)
 * both exposing health + alerts under different tabs of different pages.
 * `systems` is now the AIOps dashboard body (Ai::Analytics::DashboardService —
 * the one with MCP tool usage, via Ai::Introspection::McpToolRegistrar's
 * platform.health/platform.alerts/platform.provider_health, and genuinely live
 * per-execution data via Ai::ProviderMetric.record_metrics), not the old
 * Monitoring::UnifiedService-backed provider/agent grids. `circuit-breakers` is
 * new: one view for both the agent breakers (Ai::CircuitBreaker, resettable,
 * reused from Autonomy → Security) and the provider breakers
 * (Ai::CircuitBreakerRegistry, also resettable — previously dead
 * MonitoringApiService methods, now wired up), under distinct labels.
 *
 * Permissions are the ones each tab's OWN backend endpoint actually enforces
 * (not a blanket `ai.analytics.read` — that gated `health`/`systems` before
 * even though MonitoringController#health/#dashboard require
 * `ai.monitoring.read`, and `conversations` before even though
 * ConversationsController#index requires `ai.conversations.read`; both were
 * dead-end tabs for anyone without the real permission).
 */
export const MONITORING_TABS: PathTabSpec<MonitoringTabId>[] = [
  { key: 'systems', label: 'Systems', permission: 'ai.aiops.read', icon: React.createElement(Server, { size: 16 }) },
  { key: 'circuit-breakers', label: 'Circuit Breakers', permission: 'ai.monitoring.read', icon: React.createElement(Zap, { size: 16 }) },
  { key: 'alerts', label: 'Alerts', permission: 'ai.monitoring.read', icon: React.createElement(Bell, { size: 16 }) },
  // SelfHealingController requires ai.monitoring.read. Its own tab since fc-47
  // deleted System Health (platform health is on /app/status); it stays until
  // the status page covers its capabilities.
  { key: 'self-healing', label: 'Self-Healing', permission: 'ai.monitoring.read', icon: React.createElement(HeartPulse, { size: 16 }) },
  { key: 'conversations', label: 'Conversation Analytics', permission: 'ai.conversations.read', icon: React.createElement(MessageSquare, { size: 16 }) },
  { key: 'traces', label: 'Execution Traces', permission: 'ai_monitoring.read', icon: React.createElement(Workflow, { size: 16 }) },
  { key: 'evaluation', label: 'Evaluation', permission: 'ai.analytics.read', icon: React.createElement(ClipboardCheck, { size: 16 }) },
];

/**
 * Valid tab IDs for URL parameter validation (Observability hub).
 */
export const VALID_TAB_IDS = MONITORING_TABS.map(tab => tab.key);

/**
 * Get breadcrumbs based on active Observability tab.
 *
 * Retained for backward compatibility; ObservabilityPage computes breadcrumbs
 * from `useLocation` + `aiCrumbs(...)` directly.
 */
export const getMonitoringBreadcrumbs = (activeTab: string) => {
  const baseBreadcrumbs: Array<{ label: string; href?: string }> = [
    { label: 'Dashboard', href: '/app' },
    { label: 'AI', href: '/app/ai' },
  ];

  const activeTabInfo = MONITORING_TABS.find(tab => tab.key === activeTab);
  baseBreadcrumbs.push({ label: 'Observability', href: '/app/ai/observability' });
  if (activeTabInfo) baseBreadcrumbs.push({ label: activeTabInfo.label });

  return baseBreadcrumbs;
};

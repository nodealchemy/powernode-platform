import React from 'react';
import { HeartPulse, Server, MessageSquare, ClipboardCheck, Bell, Activity, Workflow } from 'lucide-react';
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
export type MonitoringTabId = 'health' | 'systems' | 'conversations' | 'evaluation';

/**
 * Tab definitions for the Observability hub — consumed directly by the canonical
 * `PathTabs` scaffold (one URL segment per tab). The legacy `operations`/`alerts`/
 * `credits` tabs moved out: operations + alerts now live on the Operations hub
 * (`OPERATIONS_TABS`), and billing/credits moved to the Cost domain.
 */
export const MONITORING_TABS: PathTabSpec<MonitoringTabId>[] = [
  { key: 'health', label: 'System Health', permission: 'ai.analytics.read', icon: React.createElement(HeartPulse, { size: 16 }) },
  { key: 'systems', label: 'Systems', permission: 'ai.analytics.read', icon: React.createElement(Server, { size: 16 }) },
  { key: 'conversations', label: 'Conversations', permission: 'ai.analytics.read', icon: React.createElement(MessageSquare, { size: 16 }) },
  { key: 'evaluation', label: 'Evaluation', permission: 'ai.analytics.read', icon: React.createElement(ClipboardCheck, { size: 16 }) },
];

/**
 * Path-based tab identifiers for the Operations hub (`/app/ai/operations`).
 */
export type OperationsTabId = 'aiops' | 'alerts' | 'traces';

/**
 * Tab definitions for the Operations hub — AIOps dashboard, alert management, and
 * the execution-trace viewer. Consumed by `OperationsPage` via `PathTabs`.
 */
export const OPERATIONS_TABS: PathTabSpec<OperationsTabId>[] = [
  { key: 'aiops', label: 'AIOps', permission: 'ai.aiops.read', icon: React.createElement(Activity, { size: 16 }) },
  { key: 'alerts', label: 'Alerts', permission: 'ai.aiops.read', icon: React.createElement(Bell, { size: 16 }) },
  { key: 'traces', label: 'Execution Traces', permission: 'ai_monitoring.read', icon: React.createElement(Workflow, { size: 16 }) },
];

/**
 * Valid tab IDs for URL parameter validation (Observability hub).
 */
export const VALID_TAB_IDS = MONITORING_TABS.map(tab => tab.key);

/**
 * Get breadcrumbs based on active Observability tab.
 *
 * Retained for backward compatibility; new hub pages compute breadcrumbs from
 * `useLocation` + `aiCrumbs(...)` directly (see ObservabilityPage / OperationsPage).
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

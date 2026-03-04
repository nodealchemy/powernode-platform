import React from 'react';
import { HeartPulse, Server, MessageSquare, ClipboardCheck, Bell, Coins, Activity } from 'lucide-react';

/**
 * Get color class for health score
 */
export const getHealthScoreColor = (score: number): string => {
  if (score >= 80) return 'text-theme-success';
  if (score >= 50) return 'text-theme-warning';
  return 'text-theme-error';
};

/**
 * Get background class for connection status
 */
export const getConnectionStatusColor = (isConnected: boolean): string => {
  return isConnected ? 'bg-theme-success' : 'bg-theme-error';
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
 * Tab definitions for Observability
 */
export const MONITORING_TABS: ReadonlyArray<{
  id: 'overview' | 'operations' | 'systems' | 'conversations' | 'evaluation' | 'alerts' | 'credits';
  label: string;
  icon: React.ReactNode;
  path: string;
}> = [
  { id: 'overview', label: 'System Health', icon: React.createElement(HeartPulse, { size: 16 }), path: '/' },
  { id: 'operations', label: 'Operations', icon: React.createElement(Activity, { size: 16 }), path: '/operations' },
  { id: 'systems', label: 'Systems', icon: React.createElement(Server, { size: 16 }), path: '/systems' },
  { id: 'conversations', label: 'Conversations', icon: React.createElement(MessageSquare, { size: 16 }), path: '/conversations' },
  { id: 'evaluation', label: 'Evaluation', icon: React.createElement(ClipboardCheck, { size: 16 }), path: '/evaluation' },
  { id: 'alerts', label: 'Alerts', icon: React.createElement(Bell, { size: 16 }), path: '/alerts' },
  { id: 'credits', label: 'Credits & FinOps', icon: React.createElement(Coins, { size: 16 }), path: '/credits' },
];

export type MonitoringTabId = typeof MONITORING_TABS[number]['id'];

/**
 * Valid tab IDs for URL parameter validation
 */
export const VALID_TAB_IDS = MONITORING_TABS.map(tab => tab.id);

/**
 * Get breadcrumbs based on active tab
 */
export const getMonitoringBreadcrumbs = (activeTab: string) => {
  const baseBreadcrumbs: Array<{ label: string; href?: string }> = [
    { label: 'Dashboard', href: '/app' },
    { label: 'AI', href: '/app/ai' },
  ];

  const activeTabInfo = MONITORING_TABS.find(tab => tab.id === activeTab);
  if (activeTab === 'overview') {
    baseBreadcrumbs.push({ label: 'Observability' });
  } else {
    baseBreadcrumbs.push({ label: 'Observability', href: '/app/ai/observability' });
    if (activeTabInfo) baseBreadcrumbs.push({ label: activeTabInfo.label });
  }

  return baseBreadcrumbs;
};

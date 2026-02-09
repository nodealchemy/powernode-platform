import React from 'react';
import { HeartPulse, Plug, Bot, Workflow, MessageSquare, Bell, BarChart3, Lightbulb } from 'lucide-react';

/**
 * Get color class for health score
 */
export const getHealthScoreColor = (score: number): string => {
  if (score >= 90) return 'text-theme-success';
  if (score >= 80) return 'text-theme-primary';
  if (score >= 70) return 'text-theme-warning';
  if (score >= 50) return 'text-theme-error';
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
 * Tab definitions for AI Monitoring
 */
export const MONITORING_TABS: ReadonlyArray<{
  id: 'overview' | 'providers' | 'agents' | 'workflows' | 'conversations' | 'alerts' | 'analytics' | 'learning';
  label: string;
  icon: React.ReactNode;
  path: string;
}> = [
  { id: 'overview', label: 'System Health', icon: React.createElement(HeartPulse, { size: 16 }), path: '/' },
  { id: 'providers', label: 'Providers', icon: React.createElement(Plug, { size: 16 }), path: '/providers' },
  { id: 'agents', label: 'Agents', icon: React.createElement(Bot, { size: 16 }), path: '/agents' },
  { id: 'workflows', label: 'Workflows', icon: React.createElement(Workflow, { size: 16 }), path: '/workflows' },
  { id: 'conversations', label: 'Conversations', icon: React.createElement(MessageSquare, { size: 16 }), path: '/conversations' },
  { id: 'alerts', label: 'Alerts', icon: React.createElement(Bell, { size: 16 }), path: '/alerts' },
  { id: 'analytics', label: 'Analytics', icon: React.createElement(BarChart3, { size: 16 }), path: '/analytics' },
  { id: 'learning', label: 'Learning', icon: React.createElement(Lightbulb, { size: 16 }), path: '/learning' },
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
    { label: 'Monitoring' }
  ];

  // Add active tab to breadcrumbs if not the default overview tab
  const activeTabInfo = MONITORING_TABS.find(tab => tab.id === activeTab);
  if (activeTabInfo && activeTab !== 'overview') {
    baseBreadcrumbs.push({
      label: activeTabInfo.label
    });
  }

  return baseBreadcrumbs;
};

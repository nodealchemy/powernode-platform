import type { MissionStatus, MissionType } from '../types/mission';

// --- Status ---

export const STATUS_CONFIG: Record<MissionStatus, {
  variant: 'success' | 'warning' | 'danger' | 'info' | 'outline' | 'primary';
  label: string;
  dot: string;
  pulse?: boolean;
}> = {
  draft: { variant: 'outline', label: 'Draft', dot: 'bg-theme-surface' },
  active: { variant: 'success', label: 'Active', dot: 'bg-theme-success', pulse: true },
  paused: { variant: 'warning', label: 'Paused', dot: 'bg-theme-warning' },
  completed: { variant: 'primary', label: 'Completed', dot: 'bg-theme-info' },
  failed: { variant: 'danger', label: 'Failed', dot: 'bg-theme-error' },
  cancelled: { variant: 'outline', label: 'Cancelled', dot: 'bg-theme-surface' },
};

export type StatusTabId = 'all' | 'active' | 'completed' | 'failed';

export const STATUS_TABS: { id: StatusTabId; label: string }[] = [
  { id: 'all', label: 'All' },
  { id: 'active', label: 'Active' },
  { id: 'completed', label: 'Completed' },
  { id: 'failed', label: 'Failed' },
];

export const TAB_STATUS_MAP: Record<StatusTabId, MissionStatus[] | null> = {
  all: null,
  active: ['active', 'paused', 'draft'],
  completed: ['completed'],
  failed: ['failed', 'cancelled'],
};

// --- Mission Types ---

export const MISSION_TYPE_LABELS: Record<MissionType, string> = {
  development: 'Development',
  research: 'Research',
  operations: 'Operations',
  custom: 'Custom',
};

// --- Sort ---

export const SORT_OPTIONS = [
  { key: 'updated_at', label: 'Updated' },
  { key: 'created_at', label: 'Created' },
  { key: 'name', label: 'Name' },
] as const;

// --- Utilities ---

export function timeAgo(dateStr: string | null | undefined): string {
  if (!dateStr) return '';
  const diff = Date.now() - new Date(dateStr).getTime();
  const minutes = Math.floor(diff / 60000);
  if (minutes < 1) return 'just now';
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  return `${days}d ago`;
}

export function formatDuration(ms: number | null | undefined): string {
  if (!ms) return '—';
  if (ms < 1000) return `${Math.round(ms)}ms`;
  if (ms < 60000) return `${(ms / 1000).toFixed(1)}s`;
  if (ms < 3600000) return `${Math.floor(ms / 60000)}m`;
  return `${(ms / 3600000).toFixed(1)}h`;
}

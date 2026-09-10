import type { MissionStatus, MissionType } from '../types/mission';
import { formatDurationMs, formatRelativeTimeCompact } from '@/shared/utils/formatters';

// --- Status ---

export const STATUS_CONFIG: Record<MissionStatus, {
  variant: 'success' | 'warning' | 'danger' | 'info' | 'outline' | 'primary';
  label: string;
  dot: string;
  pulse?: boolean;
}> = {
  draft: { variant: 'outline', label: 'Draft', dot: 'bg-theme-surface' },
  active: { variant: 'success', label: 'Active', dot: 'bg-theme-success-bg', pulse: true },
  paused: { variant: 'warning', label: 'Paused', dot: 'bg-theme-warning-bg' },
  completed: { variant: 'primary', label: 'Completed', dot: 'bg-theme-info-bg' },
  failed: { variant: 'danger', label: 'Failed', dot: 'bg-theme-error-bg' },
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

// Both kept as aliases (not reimplementations) — MissionExpandedRow.tsx imports
// `timeAgo` and `formatDuration` from here; the actual formatting logic now lives
// only in shared/utils/formatters.ts (IMP-01a082a3).
const missionConstantsTimeAgo = (dateStr: string | null | undefined): string =>
  formatRelativeTimeCompact(dateStr);
const missionConstantsFormatDuration = (ms: number | null | undefined): string =>
  formatDurationMs(ms, { emptyCheck: 'falsy', tiering: 'decimal-minutes', integerMinutes: true, decimalHourTier: true });
export { missionConstantsTimeAgo as timeAgo, missionConstantsFormatDuration as formatDuration };

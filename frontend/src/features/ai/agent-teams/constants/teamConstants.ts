import type { Team } from '@/shared/services/ai/TeamsApiService';
import { formatRelativeTimeCompact } from '@/shared/utils/formatters';

// --- Status ---

export const STATUS_CONFIG: Record<string, {
  variant: 'success' | 'warning' | 'danger' | 'info' | 'outline';
  label: string;
  dot: string;
}> = {
  active: { variant: 'success', label: 'Active', dot: 'bg-theme-success-bg' },
  paused: { variant: 'warning', label: 'Paused', dot: 'bg-theme-warning-bg' },
  archived: { variant: 'outline', label: 'Archived', dot: 'bg-theme-surface' },
  disbanded: { variant: 'danger', label: 'Disbanded', dot: 'bg-theme-error-bg' },
};

export type StatusTabId = 'all' | 'active' | 'paused' | 'archived';

export const STATUS_TABS: { id: StatusTabId; label: string }[] = [
  { id: 'all', label: 'All' },
  { id: 'active', label: 'Active' },
  { id: 'paused', label: 'Paused' },
  { id: 'archived', label: 'Archived' },
];

export const TAB_STATUS_MAP: Record<StatusTabId, string[] | null> = {
  all: null,
  active: ['active'],
  paused: ['paused'],
  archived: ['archived', 'disbanded'],
};

// --- Topology ---

export const TOPOLOGY_LABELS: Record<Team['team_topology'], string> = {
  hierarchical: 'Hierarchical',
  flat: 'Flat',
  mesh: 'Mesh',
  pipeline: 'Pipeline',
  hybrid: 'Hybrid',
};

// --- Sort ---

export const SORT_OPTIONS = [
  { key: 'name', label: 'Name' },
  { key: 'created_at', label: 'Created' },
  { key: 'updated_at', label: 'Updated' },
] as const;

// --- Utilities ---

// Kept as an alias (not a reimplementation) — TeamExpandedRow.tsx imports `timeAgo`
// from here; the actual formatting logic now lives only in
// shared/utils/formatters.ts (IMP-01a082a3).
const teamConstantsTimeAgo = (dateStr: string | undefined): string => formatRelativeTimeCompact(dateStr);
export { teamConstantsTimeAgo as timeAgo };

import type { AiAgent } from '@/shared/types/ai';
import { formatDurationMs, formatRelativeTimeCompact } from '@/shared/utils/formatters';

// --- Status ---

export const STATUS_CONFIG: Record<AiAgent['status'], {
  variant: 'success' | 'warning' | 'danger' | 'info' | 'outline';
  label: string;
  dot: string;
}> = {
  active: { variant: 'success', label: 'Active', dot: 'bg-theme-success-bg' },
  inactive: { variant: 'outline', label: 'Inactive', dot: 'bg-theme-surface' },
  error: { variant: 'danger', label: 'Error', dot: 'bg-theme-error-bg' },
};

export type StatusTabId = 'all' | 'active' | 'inactive' | 'error';

export const STATUS_TABS: { id: StatusTabId; label: string }[] = [
  { id: 'all', label: 'All' },
  { id: 'active', label: 'Active' },
  { id: 'inactive', label: 'Inactive' },
  { id: 'error', label: 'Error' },
];

export const TAB_STATUS_MAP: Record<StatusTabId, AiAgent['status'][] | null> = {
  all: null,
  active: ['active'],
  inactive: ['inactive'],
  error: ['error'],
};

// --- Agent types ---

export const AGENT_TYPE_LABELS: Record<string, string> = {
  assistant: 'Assistant',
  code_assistant: 'Code',
  data_analyst: 'Data',
  content_generator: 'Content',
  image_generator: 'Image',
};

// --- Trust levels ---

export const TRUST_CONFIG: Record<string, {
  variant: 'outline' | 'info' | 'success' | 'primary';
  label: string;
  icon?: boolean;
}> = {
  supervised: { variant: 'outline', label: 'Supervised', icon: true },
  monitored: { variant: 'info', label: 'Monitored' },
  trusted: { variant: 'success', label: 'Trusted' },
  autonomous: { variant: 'primary', label: 'Autonomous' },
};

// --- Sort options ---

export const SORT_OPTIONS = [
  { key: 'name', label: 'Name' },
  { key: 'created_at', label: 'Created' },
  { key: 'last_execution_at', label: 'Last Run' },
  { key: 'agent_type', label: 'Type' },
] as const;

// --- Utilities ---

// Both kept as aliases (not reimplementations) — AgentExpandedRow.tsx imports both,
// AgentsIndexTable.tsx imports `timeAgo`; the actual formatting logic now lives
// only in shared/utils/formatters.ts (IMP-01a082a3).
const agentConstantsTimeAgo = (dateStr: string | undefined): string => formatRelativeTimeCompact(dateStr);
const agentConstantsFormatDuration = (ms: number): string => formatDurationMs(ms, { emptyCheck: 'falsy' });
export { agentConstantsTimeAgo as timeAgo, agentConstantsFormatDuration as formatDuration };

export function formatTokens(tokens: number): string {
  if (tokens >= 1000000) return `${(tokens / 1000000).toFixed(1)}M`;
  if (tokens >= 1000) return `${(tokens / 1000).toFixed(1)}K`;
  return tokens.toString();
}

export function formatCost(cost: number): string {
  if (cost <= 0) return '$0.00';
  if (cost < 0.01) return `$${cost.toFixed(4)}`;
  return `$${cost.toFixed(2)}`;
}

export function successRateColor(rate: number): string {
  if (rate >= 80) return 'text-theme-success-fg';
  if (rate >= 50) return 'text-theme-warning-fg';
  return 'text-theme-error-fg';
}


// --- Executions by executor kind (HIER-P1C / IMP-e8513b30152d) ---

/**
 * The token-comparability convention for the platform-vs-Claude-Code execution
 * split, stated wherever those counts are rendered. Also in
 * docs/guides/use-powernode-from-claude.md and .claude/hooks/subagent-report.sh
 * (which sums input_tokens + cache_read_input_tokens + cache_creation_input_tokens):
 * a Claude Code run reports its FULL billed input footprint, so its token
 * figures are not comparable to a platform run's.
 */
export const CLAUDE_CODE_TOKEN_CONVENTION =
  'Claude Code runs are executed locally by a Claude Code session and reported back. ' +
  'Their input tokens include cache_read + cache_creation (the full billed input footprint), ' +
  'so they are not directly comparable to platform executions.';

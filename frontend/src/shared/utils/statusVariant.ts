import type { BadgeProps } from '@/shared/components/ui/Badge';

/**
 * The one status/severity -> Badge variant mapping. Pages used to carry their
 * own getStatusColor / getStatusBadge / getSeverityColor switch (plan §3);
 * use these with <Badge variant={...}> instead. pattern-validation.sh flags a
 * new local copy.
 *
 * Input is normalised (trimmed, lower-cased, spaces and hyphens to `_`), and
 * anything unlisted maps to 'default' — a neutral badge, never a guess.
 */

export type StatusBadgeVariant = Exclude<NonNullable<BadgeProps['variant']>, 'outline' | 'primary' | 'secondary'>;

const normalise = (value: string | null | undefined): string =>
  (value ?? '').trim().toLowerCase().replace(/[\s-]+/g, '_');

const invert = (table: Record<StatusBadgeVariant, readonly string[]>): Map<string, StatusBadgeVariant> =>
  new Map(
    (Object.entries(table) as Array<[StatusBadgeVariant, readonly string[]]>).flatMap(([variant, values]) =>
      values.map((value) => [value, variant] as const)
    )
  );

export const STATUS_VARIANTS: Record<StatusBadgeVariant, readonly string[]> = {
  success: [
    'active', 'completed', 'complete', 'succeeded', 'success', 'passed', 'healthy', 'connected', 'approved',
    'published', 'indexed', 'compliant', 'achieved', 'resolved', 'enabled', 'online', 'ready', 'verified', 'available',
  ],
  // Still working: in progress, whatever the stage.
  info: [
    'running', 'in_progress', 'analyzing', 'queued', 'scheduled', 'processing', 'syncing', 'building',
    'deploying', 'provisioning', 'preparing', 'connecting', 'indexing',
  ],
  // Needs attention.
  warning: [
    'pending', 'pending_review', 'pending_approval', 'degraded', 'warning', 'suspended', 'paused', 'stale',
    'retrying',
  ],
  danger: [
    'failed', 'failure', 'error', 'rejected', 'revoked', 'unhealthy', 'timeout', 'timed_out', 'disconnected',
    'offline', 'expired', 'abandoned', 'non_compliant', 'blocked',
  ],
  default: ['inactive', 'archived', 'draft', 'cancelled', 'canceled', 'disabled', 'unknown', 'none', 'skipped'],
};

export const SEVERITY_VARIANTS: Record<StatusBadgeVariant, readonly string[]> = {
  success: [],
  danger: ['critical', 'high', 'severe'],
  warning: ['medium', 'moderate'],
  info: ['low', 'info', 'informational'],
  default: ['none', 'unknown'],
};

const STATUS_LOOKUP = invert(STATUS_VARIANTS);
const SEVERITY_LOOKUP = invert(SEVERITY_VARIANTS);

export function statusVariant(status: string | null | undefined): StatusBadgeVariant {
  return STATUS_LOOKUP.get(normalise(status)) ?? 'default';
}

export function severityVariant(severity: string | null | undefined): StatusBadgeVariant {
  return SEVERITY_LOOKUP.get(normalise(severity)) ?? 'default';
}

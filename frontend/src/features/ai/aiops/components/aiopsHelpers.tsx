import React from 'react';
import { CheckCircle2, AlertTriangle, XCircle, Clock } from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';

/**
 * Shared formatting + presentation helpers for the AIOps dashboard sections.
 * Numeric/currency/duration helpers are reused from the agent-teams analytics
 * helpers; the AIOps-specific bits (percent, status badges, bucket labels) live
 * here. Every helper guards against null/undefined so a missing field can never
 * blank a section.
 */

export {
  formatNumber,
  formatCurrency,
  formatDuration,
} from '@/features/ai/agent-teams/components/teamAnalyticsHelpers';

/** Format a percentage. Backend success rates are already 0-100; pass `fromFraction` for 0-1 values. */
export const formatPercent = (value: number | null | undefined, fromFraction = false): string => {
  if (value == null || Number.isNaN(value)) return '—';
  const pct = fromFraction ? value * 100 : value;
  return `${pct.toFixed(1)}%`;
};

/** Format an ISO timestamp as a localized date+time, or em dash when absent/invalid. */
export const formatTimestamp = (iso: string | null | undefined): string => {
  if (!iso) return '—';
  const date = new Date(iso);
  return Number.isNaN(date.getTime()) ? '—' : date.toLocaleString();
};

/** Short axis/label form (time of day) for an hourly bucket key. */
export const formatBucketLabel = (iso: string | null | undefined): string => {
  if (!iso) return '—';
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return String(iso);
  return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
};

/** Map a 0-100 health/score to a theme text color class. */
export const scoreColorClass = (score: number | null | undefined): string => {
  if (score == null) return 'text-theme-secondary';
  if (score >= 90) return 'text-theme-success-fg';
  if (score >= 70) return 'text-theme-warning-fg';
  return 'text-theme-error-fg';
};

const HEALTH_VARIANT: Record<string, 'success' | 'warning' | 'danger' | 'info' | 'outline'> = {
  healthy: 'success',
  operational: 'success',
  active: 'success',
  degraded: 'warning',
  warning: 'warning',
  critical: 'danger',
  unhealthy: 'danger',
  down: 'danger',
};

export const getHealthBadge = (status: string | null | undefined): React.ReactElement => {
  const key = (status ?? 'unknown').toLowerCase();
  const variant = HEALTH_VARIANT[key] ?? 'outline';
  const label = status ? status.charAt(0).toUpperCase() + status.slice(1) : 'Unknown';
  return <Badge variant={variant} size="sm">{label}</Badge>;
};

export const getStatusIcon = (status: string | null | undefined): React.ReactElement => {
  switch ((status ?? '').toLowerCase()) {
    case 'healthy':
    case 'operational':
    case 'active':
      return <CheckCircle2 className="h-4 w-4 text-theme-success-fg" />;
    case 'degraded':
    case 'warning':
      return <AlertTriangle className="h-4 w-4 text-theme-warning-fg" />;
    case 'critical':
    case 'unhealthy':
    case 'down':
      return <XCircle className="h-4 w-4 text-theme-error-fg" />;
    default:
      return <Clock className="h-4 w-4 text-theme-tertiary" />;
  }
};

const SEVERITY_VARIANT: Record<string, 'danger' | 'warning' | 'info'> = {
  critical: 'danger',
  error: 'danger',
  warning: 'warning',
  info: 'info',
};

export const getSeverityBadge = (severity: string | null | undefined): React.ReactElement => {
  const key = (severity ?? 'info').toLowerCase();
  const variant = SEVERITY_VARIANT[key] ?? 'info';
  const label = severity ? severity.charAt(0).toUpperCase() + severity.slice(1) : 'Info';
  return <Badge variant={variant} size="sm">{label}</Badge>;
};

const CIRCUIT_VARIANT: Record<string, 'success' | 'warning' | 'danger' | 'outline'> = {
  closed: 'success',
  half_open: 'warning',
  open: 'danger',
};

export const getCircuitBadge = (state: string | null | undefined): React.ReactElement => {
  const key = (state ?? 'unknown').toLowerCase();
  const variant = CIRCUIT_VARIANT[key] ?? 'outline';
  const label = state ? state.replace(/_/g, ' ') : 'unknown';
  return <Badge variant={variant} size="sm" className="capitalize">{label}</Badge>;
};

import { useState } from 'react';
import { ChevronDown, ChevronRight } from 'lucide-react';
import { formatDurationMs, formatFileSize } from '@/shared/utils/formatters';

interface DetailSectionProps {
  title: string;
  icon?: React.ReactNode;
  defaultOpen?: boolean;
  children: React.ReactNode;
}

export function DetailSection({ title, icon, defaultOpen = true, children }: DetailSectionProps) {
  const [open, setOpen] = useState(defaultOpen);

  return (
    <div className="border border-theme rounded-lg overflow-hidden">
      <button
        onClick={() => setOpen(!open)}
        className="w-full flex items-center gap-2 px-3 py-2 text-sm font-medium text-theme-primary bg-theme-surface hover:bg-theme-surface-hover transition-colors"
      >
        {open ? <ChevronDown className="w-4 h-4" /> : <ChevronRight className="w-4 h-4" />}
        {icon && <span className="text-theme-tertiary">{icon}</span>}
        {title}
      </button>
      {open && <div className="p-3 border-t border-theme">{children}</div>}
    </div>
  );
}

interface StatCardProps {
  label: string;
  value: string | number | null | undefined;
  icon?: React.ReactNode;
  variant?: 'default' | 'success' | 'warning' | 'danger';
}

export function StatCard({ label, value, icon, variant = 'default' }: StatCardProps) {
  if (value === null || value === undefined) return null;

  const variantClasses = {
    default: 'text-theme-primary',
    success: 'text-theme-success-fg',
    warning: 'text-theme-warning-fg',
    danger: 'text-theme-error-fg',
  };

  return (
    <div className="flex flex-col gap-0.5 p-2.5 rounded-lg bg-theme-surface border border-theme">
      <div className="flex items-center gap-1.5 text-xs text-theme-tertiary">
        {icon}
        {label}
      </div>
      <div className={`text-sm font-semibold ${variantClasses[variant]}`}>
        {value}
      </div>
    </div>
  );
}

// Both kept as aliases (not reimplementations) — GitResourceDetail, RunnerJobDetail,
// ExecutionOutputDetail, ArtifactContentViewer, ReviewDetail, TrajectoryDetail
// (formatDuration) and SharedMemoryDetail (formatBytes) import these from here; the
// actual formatting logic now lives only in shared/utils/formatters.ts (IMP-01a082a3).
const detailSectionFormatDuration = (ms: number | null | undefined): string =>
  formatDurationMs(ms, { emptyValue: 'N/A', subSecond: 'raw', tiering: 'decimal-minutes' });
const detailSectionFormatBytes = (bytes: number | null | undefined): string =>
  formatFileSize(bytes, { emptyValue: 'N/A', capAtMB: true, decimals: 1 });
export { detailSectionFormatDuration as formatDuration, detailSectionFormatBytes as formatBytes };

export function formatTimestamp(ts: string | null | undefined): string {
  if (!ts) return 'N/A';
  return new Date(ts).toLocaleString();
}

export function StatusBadge({ status, className = '' }: { status: string; className?: string }) {
  const colorMap: Record<string, string> = {
    completed: 'bg-theme-success-fg/10 text-theme-success-fg',
    active: 'bg-theme-success-fg/10 text-theme-success-fg',
    ready: 'bg-theme-success-fg/10 text-theme-success-fg',
    available: 'bg-theme-success-fg/10 text-theme-success-fg',
    approved: 'bg-theme-success-fg/10 text-theme-success-fg',
    running: 'bg-theme-info-fg/10 text-theme-info-fg',
    in_progress: 'bg-theme-info-fg/10 text-theme-info-fg',
    in_use: 'bg-theme-info-fg/10 text-theme-info-fg',
    building: 'bg-theme-info-fg/10 text-theme-info-fg',
    pending: 'bg-theme-warning-fg/10 text-theme-warning-fg',
    creating: 'bg-theme-warning-fg/10 text-theme-warning-fg',
    dispatched: 'bg-theme-warning-fg/10 text-theme-warning-fg',
    failed: 'bg-theme-error-fg/10 text-theme-error-fg',
    conflict: 'bg-theme-error-fg/10 text-theme-error-fg',
    rejected: 'bg-theme-error-fg/10 text-theme-error-fg',
    rolled_back: 'bg-theme-error-fg/10 text-theme-error-fg',
    cancelled: 'bg-theme-background-secondary/10 text-theme-tertiary',
    archived: 'bg-theme-background-secondary/10 text-theme-tertiary',
    cleaned_up: 'bg-theme-background-secondary/10 text-theme-tertiary',
  };

  const colors = colorMap[status] || 'bg-theme-surface text-theme-secondary';

  return (
    <span className={`inline-flex px-2 py-0.5 text-xs font-medium rounded-full ${colors} ${className}`}>
      {status.replace(/_/g, ' ')}
    </span>
  );
}

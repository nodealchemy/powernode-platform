import { useState } from 'react';
import { ChevronDown, ChevronRight } from 'lucide-react';

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
    success: 'text-theme-success',
    warning: 'text-theme-warning',
    danger: 'text-theme-error',
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

export function formatDuration(ms: number | null | undefined): string {
  if (ms === null || ms === undefined) return 'N/A';
  if (ms < 1000) return `${ms}ms`;
  if (ms < 60000) return `${(ms / 1000).toFixed(1)}s`;
  return `${(ms / 60000).toFixed(1)}m`;
}

export function formatBytes(bytes: number | null | undefined): string {
  if (bytes === null || bytes === undefined) return 'N/A';
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

export function formatTimestamp(ts: string | null | undefined): string {
  if (!ts) return 'N/A';
  return new Date(ts).toLocaleString();
}

export function StatusBadge({ status, className = '' }: { status: string; className?: string }) {
  const colorMap: Record<string, string> = {
    completed: 'bg-theme-success/10 text-theme-success',
    active: 'bg-theme-success/10 text-theme-success',
    ready: 'bg-theme-success/10 text-theme-success',
    available: 'bg-theme-success/10 text-theme-success',
    approved: 'bg-theme-success/10 text-theme-success',
    running: 'bg-theme-info/10 text-theme-info',
    in_progress: 'bg-theme-info/10 text-theme-info',
    in_use: 'bg-theme-info/10 text-theme-info',
    building: 'bg-theme-info/10 text-theme-info',
    pending: 'bg-theme-warning/10 text-theme-warning',
    creating: 'bg-theme-warning/10 text-theme-warning',
    dispatched: 'bg-theme-warning/10 text-theme-warning',
    failed: 'bg-theme-error/10 text-theme-error',
    conflict: 'bg-theme-error/10 text-theme-error',
    rejected: 'bg-theme-error/10 text-theme-error',
    rolled_back: 'bg-theme-error/10 text-theme-error',
    cancelled: 'bg-theme-tertiary/10 text-theme-tertiary',
    archived: 'bg-theme-tertiary/10 text-theme-tertiary',
    cleaned_up: 'bg-theme-tertiary/10 text-theme-tertiary',
  };

  const colors = colorMap[status] || 'bg-theme-surface text-theme-secondary';

  return (
    <span className={`inline-flex px-2 py-0.5 text-xs font-medium rounded-full ${colors} ${className}`}>
      {status.replace(/_/g, ' ')}
    </span>
  );
}

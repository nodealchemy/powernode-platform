import type { InstanceStatus, ExecutionStatus } from '../types';

interface IntegrationStatusBadgeProps {
  status: InstanceStatus | ExecutionStatus;
  size?: 'sm' | 'md' | 'lg';
}

const statusConfig: Record<string, { label: string; classes: string }> = {
  // Instance statuses
  active: {
    label: 'Active',
    classes: 'bg-theme-success bg-opacity-10 text-theme-success',
  },
  pending: {
    label: 'Pending',
    classes: 'bg-theme-warning bg-opacity-10 text-theme-warning',
  },
  paused: {
    label: 'Paused',
    classes: 'bg-theme-surface text-theme-tertiary',
  },
  error: {
    label: 'Error',
    classes: 'bg-theme-error bg-opacity-10 text-theme-error',
  },
  // Execution statuses
  queued: {
    label: 'Queued',
    classes: 'bg-theme-warning bg-opacity-10 text-theme-warning',
  },
  running: {
    label: 'Running',
    classes: 'bg-theme-info bg-opacity-10 text-theme-info',
  },
  completed: {
    label: 'Completed',
    classes: 'bg-theme-success bg-opacity-10 text-theme-success',
  },
  failed: {
    label: 'Failed',
    classes: 'bg-theme-error bg-opacity-10 text-theme-error',
  },
  cancelled: {
    label: 'Cancelled',
    classes: 'bg-theme-surface text-theme-tertiary',
  },
};

const sizeClasses = {
  sm: 'px-2 py-0.5 text-xs',
  md: 'px-2.5 py-1 text-sm',
  lg: 'px-3 py-1.5 text-sm',
};

export function IntegrationStatusBadge({
  status,
  size = 'md',
}: IntegrationStatusBadgeProps) {
  const config = statusConfig[status] || {
    label: status,
    classes: 'bg-theme-surface text-theme-secondary',
  };

  return (
    <span
      className={`inline-flex items-center rounded-full font-medium ${config.classes} ${sizeClasses[size]}`}
    >
      {config.label}
    </span>
  );
}

import React from 'react';

type StatusType =
  | 'verified'
  | 'unverified'
  | 'quarantined'
  | 'active'
  | 'inactive'
  | 'pending'
  | 'error'
  | 'draft'
  | 'completed'
  | 'failed'
  | 'expired'
  | 'running'
  | 'in_progress'
  | 'suspended'
  | 'queued';

interface StatusBadgeProps {
  status: StatusType;
  size?: 'sm' | 'md';
}

const statusConfig: Record<StatusType, { bg: string; text: string; label: string }> = {
  verified: {
    bg: 'bg-theme-success-fg/10',
    text: 'text-theme-success-fg',
    label: 'Verified',
  },
  unverified: {
    bg: 'bg-theme-background-secondary/10',
    text: 'text-theme-tertiary',
    label: 'Unverified',
  },
  quarantined: {
    bg: 'bg-theme-error-fg/10',
    text: 'text-theme-error-fg',
    label: 'Quarantined',
  },
  active: {
    bg: 'bg-theme-success-fg/10',
    text: 'text-theme-success-fg',
    label: 'Active',
  },
  inactive: {
    bg: 'bg-theme-background-secondary/10',
    text: 'text-theme-tertiary',
    label: 'Inactive',
  },
  pending: {
    bg: 'bg-theme-warning-fg/10',
    text: 'text-theme-warning-fg',
    label: 'Pending',
  },
  error: {
    bg: 'bg-theme-error-fg/10',
    text: 'text-theme-error-fg',
    label: 'Error',
  },
  draft: {
    bg: 'bg-theme-background-secondary/10',
    text: 'text-theme-tertiary',
    label: 'Draft',
  },
  completed: {
    bg: 'bg-theme-success-fg/10',
    text: 'text-theme-success-fg',
    label: 'Completed',
  },
  failed: {
    bg: 'bg-theme-error-fg/10',
    text: 'text-theme-error-fg',
    label: 'Failed',
  },
  expired: {
    bg: 'bg-theme-warning-fg/10',
    text: 'text-theme-warning-fg',
    label: 'Expired',
  },
  running: {
    bg: 'bg-theme-info-fg/10',
    text: 'text-theme-info-fg',
    label: 'Running',
  },
  in_progress: {
    bg: 'bg-theme-info-fg/10',
    text: 'text-theme-info-fg',
    label: 'In Progress',
  },
  suspended: {
    bg: 'bg-theme-error-fg/10',
    text: 'text-theme-error-fg',
    label: 'Suspended',
  },
  queued: {
    bg: 'bg-theme-background-secondary/10',
    text: 'text-theme-tertiary',
    label: 'Queued',
  },
};

export const StatusBadge: React.FC<StatusBadgeProps> = ({ status, size = 'md' }) => {
  const config = statusConfig[status] || statusConfig.pending;
  const sizeClasses = size === 'sm' ? 'px-1.5 py-0.5 text-xs' : 'px-2 py-1 text-xs';

  return (
    <span className={`inline-flex items-center rounded-full font-medium ${config.bg} ${config.text} ${sizeClasses}`}>
      {config.label}
    </span>
  );
};

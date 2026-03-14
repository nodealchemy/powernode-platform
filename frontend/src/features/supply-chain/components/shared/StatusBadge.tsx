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
    bg: 'bg-theme-success/10',
    text: 'text-theme-success',
    label: 'Verified',
  },
  unverified: {
    bg: 'bg-theme-muted/10',
    text: 'text-theme-muted',
    label: 'Unverified',
  },
  quarantined: {
    bg: 'bg-theme-error/10',
    text: 'text-theme-error',
    label: 'Quarantined',
  },
  active: {
    bg: 'bg-theme-success/10',
    text: 'text-theme-success',
    label: 'Active',
  },
  inactive: {
    bg: 'bg-theme-muted/10',
    text: 'text-theme-muted',
    label: 'Inactive',
  },
  pending: {
    bg: 'bg-theme-warning/10',
    text: 'text-theme-warning',
    label: 'Pending',
  },
  error: {
    bg: 'bg-theme-error/10',
    text: 'text-theme-error',
    label: 'Error',
  },
  draft: {
    bg: 'bg-theme-muted/10',
    text: 'text-theme-muted',
    label: 'Draft',
  },
  completed: {
    bg: 'bg-theme-success/10',
    text: 'text-theme-success',
    label: 'Completed',
  },
  failed: {
    bg: 'bg-theme-error/10',
    text: 'text-theme-error',
    label: 'Failed',
  },
  expired: {
    bg: 'bg-theme-warning/10',
    text: 'text-theme-warning',
    label: 'Expired',
  },
  running: {
    bg: 'bg-theme-info/10',
    text: 'text-theme-info',
    label: 'Running',
  },
  in_progress: {
    bg: 'bg-theme-info/10',
    text: 'text-theme-info',
    label: 'In Progress',
  },
  suspended: {
    bg: 'bg-theme-error/10',
    text: 'text-theme-error',
    label: 'Suspended',
  },
  queued: {
    bg: 'bg-theme-muted/10',
    text: 'text-theme-muted',
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

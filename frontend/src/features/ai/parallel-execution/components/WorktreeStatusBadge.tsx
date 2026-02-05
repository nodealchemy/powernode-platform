import React from 'react';
import { Badge } from '@/shared/components/ui/Badge';
import type { WorktreeStatus, ParallelSessionStatus, MergeOperationStatus } from '../types';

const sessionStatusConfig: Record<ParallelSessionStatus, { variant: 'success' | 'warning' | 'danger' | 'info' | 'outline'; label: string }> = {
  pending: { variant: 'outline', label: 'Pending' },
  provisioning: { variant: 'info', label: 'Provisioning' },
  active: { variant: 'info', label: 'Active' },
  merging: { variant: 'warning', label: 'Merging' },
  completed: { variant: 'success', label: 'Completed' },
  failed: { variant: 'danger', label: 'Failed' },
  cancelled: { variant: 'outline', label: 'Cancelled' },
};

const worktreeStatusConfig: Record<WorktreeStatus, { variant: 'success' | 'warning' | 'danger' | 'info' | 'outline'; label: string }> = {
  pending: { variant: 'outline', label: 'Pending' },
  creating: { variant: 'info', label: 'Creating' },
  ready: { variant: 'info', label: 'Ready' },
  in_use: { variant: 'warning', label: 'In Use' },
  completed: { variant: 'success', label: 'Completed' },
  merged: { variant: 'success', label: 'Merged' },
  cleaned_up: { variant: 'outline', label: 'Cleaned Up' },
  failed: { variant: 'danger', label: 'Failed' },
};

const mergeStatusConfig: Record<MergeOperationStatus, { variant: 'success' | 'warning' | 'danger' | 'info' | 'outline'; label: string }> = {
  pending: { variant: 'outline', label: 'Pending' },
  in_progress: { variant: 'info', label: 'In Progress' },
  completed: { variant: 'success', label: 'Completed' },
  conflict: { variant: 'danger', label: 'Conflict' },
  failed: { variant: 'danger', label: 'Failed' },
  rolled_back: { variant: 'warning', label: 'Rolled Back' },
};

interface StatusBadgeProps {
  status: string;
  type: 'session' | 'worktree' | 'merge';
  size?: 'sm' | 'md';
}

export const WorktreeStatusBadge: React.FC<StatusBadgeProps> = ({ status, type, size }) => {
  const config = type === 'session'
    ? sessionStatusConfig[status as ParallelSessionStatus]
    : type === 'worktree'
      ? worktreeStatusConfig[status as WorktreeStatus]
      : mergeStatusConfig[status as MergeOperationStatus];

  if (!config) {
    return <Badge variant="outline" size={size}>{status}</Badge>;
  }

  return <Badge variant={config.variant} size={size}>{config.label}</Badge>;
};

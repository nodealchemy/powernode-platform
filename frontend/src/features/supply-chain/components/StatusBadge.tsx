import React from 'react';
import { Badge } from '@/shared/components/ui/Badge';

type Status = 'active' | 'inactive' | 'pending' | 'suspended';

interface StatusBadgeProps {
  status: Status;
  className?: string;
}

export const StatusBadge: React.FC<StatusBadgeProps> = ({ status, className }) => {
  const variantMap: Record<Status, 'success' | 'secondary' | 'warning' | 'danger'> = {
    active: 'success',
    inactive: 'secondary',
    pending: 'warning',
    suspended: 'danger',
  };

  const labelMap: Record<Status, string> = {
    active: 'Active',
    inactive: 'Inactive',
    pending: 'Pending',
    suspended: 'Suspended',
  };

  return (
    <Badge variant={variantMap[status]} size="sm" className={className}>
      {labelMap[status]}
    </Badge>
  );
};

import React from 'react';
import { swarmApi } from '../services/swarmApi';
import type { ClusterStatus } from '../types';

interface ClusterStatusBadgeProps {
  status: ClusterStatus;
  size?: 'sm' | 'md';
}

export const ClusterStatusBadge: React.FC<ClusterStatusBadgeProps> = ({ status, size = 'sm' }) => {
  const colorClasses = swarmApi.getClusterStatusColor(status);
  const sizeClasses = size === 'sm' ? 'px-2 py-0.5 text-xs' : 'px-3 py-1 text-sm';

  return (
    <span className={`inline-flex items-center gap-1.5 rounded-full font-medium ${colorClasses} ${sizeClasses}`}>
      <span className={`w-1.5 h-1.5 rounded-full ${
        status === 'connected' ? 'bg-theme-success' :
        status === 'error' ? 'bg-theme-error' :
        status === 'pending' ? 'bg-theme-warning' :
        status === 'maintenance' ? 'bg-theme-info' :
        'bg-theme-tertiary'
      }`} />
      {status}
    </span>
  );
};

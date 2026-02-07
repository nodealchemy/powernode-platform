import React from 'react';
import { dockerApi } from '../services/dockerApi';
import type { HostStatus } from '../types';

interface HostStatusBadgeProps {
  status: HostStatus;
  size?: 'sm' | 'md';
}

export const HostStatusBadge: React.FC<HostStatusBadgeProps> = ({ status, size = 'sm' }) => {
  const colorClasses = dockerApi.getHostStatusColor(status);
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

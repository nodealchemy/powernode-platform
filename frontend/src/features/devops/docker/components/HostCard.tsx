import React from 'react';
import { Card } from '@/shared/components/ui/Card';
import { HostStatusBadge } from './HostStatusBadge';
import type { DockerHostSummary } from '../types';

interface HostCardProps {
  host: DockerHostSummary;
  onClick?: (hostId: string) => void;
}

export const HostCard: React.FC<HostCardProps> = ({ host, onClick }) => {
  const environmentColors: Record<string, string> = {
    production: 'bg-theme-error bg-opacity-10 text-theme-error',
    staging: 'bg-theme-warning bg-opacity-10 text-theme-warning',
    development: 'bg-theme-info bg-opacity-10 text-theme-info',
    custom: 'bg-theme-surface text-theme-secondary',
  };

  return (
    <Card
      variant="default"
      padding="lg"
      hoverable
      clickable={!!onClick}
      onClick={() => onClick?.(host.id)}
    >
      <div className="space-y-3">
        <div className="flex items-start justify-between">
          <div className="min-w-0 flex-1">
            <h3 className="text-sm font-semibold text-theme-primary truncate">{host.name}</h3>
            <p className="text-xs text-theme-tertiary mt-0.5 truncate">{host.api_endpoint}</p>
          </div>
          <HostStatusBadge status={host.status} />
        </div>

        <div className="flex items-center gap-2">
          <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium ${environmentColors[host.environment] || environmentColors.custom}`}>
            {host.environment}
          </span>
        </div>

        <div className="grid grid-cols-2 gap-3 pt-2 border-t border-theme">
          <div>
            <p className="text-xs text-theme-tertiary">Containers</p>
            <p className="text-sm font-medium text-theme-primary">{host.container_count}</p>
          </div>
          <div>
            <p className="text-xs text-theme-tertiary">Images</p>
            <p className="text-sm font-medium text-theme-primary">{host.image_count}</p>
          </div>
        </div>

        {host.last_synced_at && (
          <p className="text-xs text-theme-tertiary">
            Last synced: {new Date(host.last_synced_at).toLocaleString()}
          </p>
        )}
      </div>
    </Card>
  );
};

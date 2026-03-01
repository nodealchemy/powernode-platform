import React from 'react';
import { Card } from '@/shared/components/ui/Card';
import { ClusterStatusBadge } from './ClusterStatusBadge';
import type { SwarmClusterSummary } from '../types';

interface ClusterCardProps {
  cluster: SwarmClusterSummary;
  onClick?: () => void;
}

export const ClusterCard: React.FC<ClusterCardProps> = ({ cluster, onClick }) => {
  return (
    <Card variant="default" hoverable clickable={!!onClick} padding="lg" onClick={onClick}>
      <div className="flex items-start justify-between mb-3">
        <div className="flex-1 min-w-0">
          <h3 className="text-lg font-semibold text-theme-primary truncate">{cluster.name}</h3>
          <p className="text-sm text-theme-tertiary truncate">{cluster.api_endpoint}</p>
        </div>
        <ClusterStatusBadge status={cluster.status} />
      </div>
      <div className="flex items-center gap-4 text-sm text-theme-secondary">
        <span className="px-2 py-0.5 rounded bg-theme-surface text-theme-secondary text-xs font-medium">
          {cluster.environment}
        </span>
        <span>{cluster.node_count} nodes</span>
        <span>{cluster.service_count} services</span>
      </div>
      {cluster.last_synced_at && (
        <p className="text-xs text-theme-tertiary mt-2">
          Last synced: {new Date(cluster.last_synced_at).toLocaleString()}
        </p>
      )}
    </Card>
  );
};

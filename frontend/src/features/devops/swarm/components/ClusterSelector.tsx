import React from 'react';
import { useClusterContext } from '../hooks/useClusterContext';
import { ClusterStatusBadge } from './ClusterStatusBadge';

export const ClusterSelector: React.FC = () => {
  const { clusters, selectedClusterId, selectCluster, isLoading } = useClusterContext();

  if (isLoading) {
    return (
      <div className="flex items-center gap-2">
        <span className="text-sm text-theme-tertiary">Loading clusters...</span>
      </div>
    );
  }

  if (clusters.length === 0) {
    return (
      <div className="flex items-center gap-2">
        <span className="text-sm text-theme-tertiary">No clusters configured</span>
      </div>
    );
  }

  const selectedCluster = clusters.find((c) => c.id === selectedClusterId);

  return (
    <div className="flex items-center gap-3">
      <label className="text-sm font-medium text-theme-secondary">Cluster:</label>
      <select
        className="input-theme text-sm min-w-[200px]"
        value={selectedClusterId || ''}
        onChange={(e) => selectCluster(e.target.value || null)}
      >
        <option value="">Select cluster...</option>
        {clusters.map((cluster) => (
          <option key={cluster.id} value={cluster.id}>
            {cluster.name} ({cluster.environment})
          </option>
        ))}
      </select>
      {selectedCluster && <ClusterStatusBadge status={selectedCluster.status} />}
    </div>
  );
};

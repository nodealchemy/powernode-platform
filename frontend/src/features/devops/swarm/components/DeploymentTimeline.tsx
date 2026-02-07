import React from 'react';
import { XCircle } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { swarmApi } from '../services/swarmApi';
import type { SwarmDeploymentSummary } from '../types';

interface DeploymentTimelineProps {
  deployments: SwarmDeploymentSummary[];
  onCancel?: (deploymentId: string) => void;
}

export const DeploymentTimeline: React.FC<DeploymentTimelineProps> = ({ deployments, onCancel }) => {
  if (deployments.length === 0) {
    return <p className="text-center py-8 text-theme-tertiary">No deployments found.</p>;
  }

  return (
    <div className="relative">
      <div className="absolute left-6 top-0 bottom-0 w-0.5 bg-theme-surface" />

      <div className="space-y-4">
        {deployments.map((deployment) => {
          const statusColor = swarmApi.getDeploymentStatusColor(deployment.status);
          const isActive = deployment.status === 'running' || deployment.status === 'pending';

          return (
            <div key={deployment.id} className="relative flex items-start gap-4 pl-12">
              <div className={`absolute left-4 w-4 h-4 rounded-full border-2 border-theme-background ${
                deployment.status === 'completed' ? 'bg-theme-success' :
                deployment.status === 'failed' ? 'bg-theme-error' :
                deployment.status === 'running' ? 'bg-theme-info' :
                deployment.status === 'cancelled' ? 'bg-theme-tertiary' :
                'bg-theme-warning'
              }`} />

              <div className="flex-1 p-3 rounded-lg bg-theme-surface border border-theme">
                <div className="flex items-start justify-between">
                  <div>
                    <div className="flex items-center gap-2">
                      <span className="text-sm font-semibold text-theme-primary capitalize">
                        {deployment.deployment_type.replace('_', ' ')}
                      </span>
                      <span className={`px-2 py-0.5 rounded text-xs font-medium ${statusColor}`}>
                        {deployment.status}
                      </span>
                    </div>
                    <div className="flex items-center gap-3 mt-1 text-xs text-theme-tertiary">
                      {deployment.trigger_source && <span>Source: {deployment.trigger_source}</span>}
                      {deployment.triggered_by && <span>By: {deployment.triggered_by}</span>}
                      {deployment.duration_ms !== undefined && deployment.duration_ms !== null && (
                        <span>Duration: {swarmApi.formatDuration(deployment.duration_ms)}</span>
                      )}
                    </div>
                  </div>
                  <div className="flex items-center gap-2">
                    <span className="text-xs text-theme-tertiary">
                      {deployment.started_at ? new Date(deployment.started_at).toLocaleString() : new Date(deployment.created_at).toLocaleString()}
                    </span>
                    {isActive && onCancel && (
                      <Button size="xs" variant="danger" onClick={() => onCancel(deployment.id)} title="Cancel">
                        <XCircle className="w-3.5 h-3.5" />
                      </Button>
                    )}
                  </div>
                </div>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
};

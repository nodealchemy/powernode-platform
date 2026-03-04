import React from 'react';
import { ChevronRight, Rocket, XCircle, Trash2, RefreshCw, Scale, RotateCcw } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { StackComposeEditor } from './StackComposeEditor';
import { swarmApi } from '../services/swarmApi';
import type { SwarmStackSummary, SwarmStack, SwarmServiceSummary } from '../types';

interface ExpandedData {
  details: SwarmStack | null;
  services: SwarmServiceSummary[];
  isLoading: boolean;
  error: string | null;
}

interface StackCardProps {
  stack: SwarmStackSummary;
  isExpanded: boolean;
  expandedData: ExpandedData | null;
  onToggleExpand: () => void;
  onDeploy: () => void;
  onRemove: () => void;
  onDelete: () => void;
  onScaleService: (service: SwarmServiceSummary) => void;
  onRollbackService: (service: SwarmServiceSummary) => void;
}

export const StackCard: React.FC<StackCardProps> = ({
  stack,
  isExpanded,
  expandedData,
  onToggleExpand,
  onDeploy,
  onRemove,
  onDelete,
  onScaleService,
  onRollbackService,
}) => {
  return (
    <Card variant="default" padding="md">
      {/* Collapsed header — always visible */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3 flex-1 min-w-0">
          <button
            onClick={onToggleExpand}
            className="p-1 rounded hover:bg-theme-surface transition-transform"
            title={isExpanded ? 'Collapse' : 'Expand'}
          >
            <ChevronRight className={`w-4 h-4 text-theme-tertiary transition-transform ${isExpanded ? 'rotate-90' : ''}`} />
          </button>
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-3">
              <h3 className="text-base font-semibold text-theme-primary">{stack.name}</h3>
              <span className={`px-2 py-0.5 rounded text-xs font-medium ${swarmApi.getStackStatusColor(stack.status)}`}>
                {stack.status}
              </span>
              {stack.source === 'discovered' && (
                <span className="px-2 py-0.5 rounded text-xs font-medium bg-theme-info/10 text-theme-info">
                  Discovered
                </span>
              )}
            </div>
            <div className="flex items-center gap-4 mt-1 text-xs text-theme-tertiary">
              <span>{stack.service_count} services</span>
              <span>{stack.deploy_count} deploys</span>
              {stack.last_deployed_at && <span>Last: {new Date(stack.last_deployed_at).toLocaleString()}</span>}
            </div>
          </div>
        </div>
        <div className="flex items-center gap-1">
          <Button size="xs" variant="ghost" onClick={onDeploy} title="Deploy">
            <Rocket className="w-3.5 h-3.5" />
          </Button>
          <Button size="xs" variant="ghost" onClick={onRemove} title="Remove">
            <XCircle className="w-3.5 h-3.5" />
          </Button>
          <Button size="xs" variant="danger" onClick={onDelete} title="Delete">
            <Trash2 className="w-3.5 h-3.5" />
          </Button>
        </div>
      </div>

      {/* Expanded section */}
      {isExpanded && (
        <div className="border-t border-theme mt-3 pt-3 space-y-4">
          {expandedData?.isLoading ? (
            <div className="flex items-center justify-center py-6">
              <RefreshCw className="w-5 h-5 animate-spin text-theme-tertiary" />
              <span className="ml-2 text-sm text-theme-secondary">Loading stack details...</span>
            </div>
          ) : expandedData?.error ? (
            <div className="text-center py-4">
              <p className="text-sm text-theme-error mb-2">{expandedData.error}</p>
              <Button size="xs" variant="secondary" onClick={onToggleExpand}>Retry</Button>
            </div>
          ) : (
            <>
              {/* A. Services list */}
              {expandedData && expandedData.services.length > 0 && (
                <div>
                  <h4 className="text-xs font-semibold text-theme-secondary uppercase tracking-wider mb-2">Services</h4>
                  <div className="space-y-1.5">
                    {expandedData.services.map((svc) => (
                      <ServiceRow
                        key={svc.id}
                        service={svc}
                        onScale={() => onScaleService(svc)}
                        onRollback={() => onRollbackService(svc)}
                      />
                    ))}
                  </div>
                </div>
              )}

              {/* B. Stack metadata */}
              {expandedData?.details && (
                <div>
                  <h4 className="text-xs font-semibold text-theme-secondary uppercase tracking-wider mb-2">Details</h4>
                  <dl className="grid grid-cols-2 gap-x-6 gap-y-1 text-sm">
                    <dt className="text-theme-tertiary">Created</dt>
                    <dd className="text-theme-primary">{new Date(expandedData.details.created_at).toLocaleString()}</dd>
                    <dt className="text-theme-tertiary">Updated</dt>
                    <dd className="text-theme-primary">{new Date(expandedData.details.updated_at).toLocaleString()}</dd>
                  </dl>
                  {Object.keys(expandedData.details.compose_variables).length > 0 && (
                    <div className="mt-2">
                      <h5 className="text-xs text-theme-tertiary mb-1">Variables</h5>
                      <div className="flex flex-wrap gap-1">
                        {Object.entries(expandedData.details.compose_variables).map(([k, v]) => (
                          <span key={k} className="px-1.5 py-0.5 rounded bg-theme-surface text-xs text-theme-secondary font-mono">
                            {k}={v}
                          </span>
                        ))}
                      </div>
                    </div>
                  )}
                </div>
              )}

              {/* C. Compose file */}
              {expandedData?.details?.compose_file && (
                <div>
                  <h4 className="text-xs font-semibold text-theme-secondary uppercase tracking-wider mb-2">Compose File</h4>
                  <StackComposeEditor value={expandedData.details.compose_file} onChange={() => {}} readOnly />
                </div>
              )}
            </>
          )}
        </div>
      )}
    </Card>
  );
};

// ─── Compact inline service row ───────────────────────────────────────

interface ServiceRowProps {
  service: SwarmServiceSummary;
  onScale: () => void;
  onRollback: () => void;
}

const ServiceRow: React.FC<ServiceRowProps> = ({ service, onScale, onRollback }) => {
  const healthColor = swarmApi.getHealthPercentageColor(service.health_percentage);
  const healthWidth = Math.min(100, Math.max(0, service.health_percentage));
  const replicaColor = service.running_replicas >= service.desired_replicas ? 'text-theme-success' : 'text-theme-warning';

  return (
    <div className="flex items-center gap-3 px-2 py-1.5 rounded hover:bg-theme-surface/50 group">
      {/* Name + image */}
      <div className="flex-1 min-w-0">
        <span className="text-sm font-medium text-theme-primary">{service.service_name}</span>
        <span className="ml-2 text-xs text-theme-tertiary truncate">{service.image}</span>
      </div>

      {/* Mode badge */}
      <span className="px-1.5 py-0.5 rounded bg-theme-surface text-xs text-theme-secondary capitalize shrink-0">
        {service.mode}
      </span>

      {/* Replicas */}
      <span className={`text-xs font-semibold shrink-0 ${replicaColor}`}>
        {service.running_replicas}/{service.desired_replicas}
      </span>

      {/* Mini health bar */}
      <div className="w-16 h-1 bg-theme-surface rounded-full overflow-hidden shrink-0">
        <div
          className={`h-full rounded-full ${
            service.health_percentage >= 100 ? 'bg-theme-success' :
            service.health_percentage >= 50 ? 'bg-theme-warning' :
            'bg-theme-error'
          }`}
          style={{ width: `${healthWidth}%` }}
        />
      </div>

      {/* Health % */}
      <span className={`text-xs font-medium w-8 text-right shrink-0 ${healthColor}`}>
        {service.health_percentage}%
      </span>

      {/* Ports */}
      {service.ports.length > 0 && (
        <div className="flex gap-0.5 shrink-0">
          {service.ports.map((port, i) => (
            <span key={i} className="px-1 py-0.5 rounded bg-theme-surface text-xs text-theme-tertiary">
              {port.published}:{port.target}
            </span>
          ))}
        </div>
      )}

      {/* Actions */}
      <div className="flex gap-0.5 shrink-0 opacity-0 group-hover:opacity-100 transition-opacity">
        {service.mode === 'replicated' && (
          <Button size="xs" variant="ghost" onClick={onScale} title="Scale">
            <Scale className="w-3 h-3" />
          </Button>
        )}
        <Button size="xs" variant="ghost" onClick={onRollback} title="Rollback">
          <RotateCcw className="w-3 h-3" />
        </Button>
      </div>
    </div>
  );
};

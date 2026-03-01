import React from 'react';
import { ArrowUp, ArrowDown, Droplets, Trash2 } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { swarmApi } from '../services/swarmApi';
import type { SwarmNodeSummary } from '../types';

interface NodeCardProps {
  node: SwarmNodeSummary;
  onPromote?: () => void;
  onDemote?: () => void;
  onDrain?: () => void;
  onRemove?: () => void;
}

export const NodeCard: React.FC<NodeCardProps> = ({ node, onPromote, onDemote, onDrain, onRemove }) => {
  const statusColor = swarmApi.getNodeStatusColor(node.status);

  return (
    <Card variant="default" padding="md">
      <div className="flex items-start justify-between mb-3">
        <div className="flex-1 min-w-0">
          <h4 className="text-base font-semibold text-theme-primary truncate">{node.hostname}</h4>
          {node.ip_address && <p className="text-xs text-theme-tertiary">{node.ip_address}</p>}
        </div>
        <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${statusColor}`}>{node.status}</span>
      </div>

      <div className="flex items-center gap-3 mb-3 text-xs text-theme-secondary">
        <span className={`px-2 py-0.5 rounded ${node.role === 'manager' ? 'bg-theme-info bg-opacity-10 text-theme-info' : 'bg-theme-surface text-theme-secondary'}`}>
          {node.role}
        </span>
        <span className={`px-2 py-0.5 rounded ${
          node.availability === 'active' ? 'bg-theme-success bg-opacity-10 text-theme-success' :
          node.availability === 'drain' ? 'bg-theme-warning bg-opacity-10 text-theme-warning' :
          'bg-theme-surface text-theme-secondary'
        }`}>
          {node.availability}
        </span>
        {node.manager_status && (
          <span className="px-2 py-0.5 rounded bg-theme-surface text-theme-secondary">{node.manager_status}</span>
        )}
      </div>

      <div className="grid grid-cols-2 gap-2 mb-3 text-xs">
        {node.cpu_count !== undefined && (
          <div>
            <span className="text-theme-tertiary">CPUs:</span>
            <span className="ml-1 text-theme-primary">{node.cpu_count}</span>
          </div>
        )}
        {node.memory_gb !== undefined && (
          <div>
            <span className="text-theme-tertiary">Memory:</span>
            <span className="ml-1 text-theme-primary">{node.memory_gb} GB</span>
          </div>
        )}
      </div>

      {Object.keys(node.labels).length > 0 && (
        <div className="flex flex-wrap gap-1 mb-3">
          {Object.entries(node.labels).slice(0, 3).map(([key, value]) => (
            <span key={key} className="px-1.5 py-0.5 rounded bg-theme-surface text-theme-tertiary text-xs">
              {key}={value}
            </span>
          ))}
          {Object.keys(node.labels).length > 3 && (
            <span className="text-xs text-theme-tertiary">+{Object.keys(node.labels).length - 3} more</span>
          )}
        </div>
      )}

      <div className="flex items-center gap-1 border-t border-theme pt-3">
        {onPromote && (
          <Button size="xs" variant="ghost" onClick={onPromote} title="Promote to manager">
            <ArrowUp className="w-3.5 h-3.5 mr-1" /> Promote
          </Button>
        )}
        {onDemote && (
          <Button size="xs" variant="ghost" onClick={onDemote} title="Demote to worker">
            <ArrowDown className="w-3.5 h-3.5 mr-1" /> Demote
          </Button>
        )}
        {onDrain && (
          <Button size="xs" variant="warning" onClick={onDrain} title="Drain node">
            <Droplets className="w-3.5 h-3.5 mr-1" /> Drain
          </Button>
        )}
        {onRemove && (
          <Button size="xs" variant="danger" onClick={onRemove} title="Remove node">
            <Trash2 className="w-3.5 h-3.5" />
          </Button>
        )}
      </div>
    </Card>
  );
};

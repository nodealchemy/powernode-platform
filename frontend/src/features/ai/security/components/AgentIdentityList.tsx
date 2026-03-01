import React, { useState } from 'react';
import { Key, RotateCw, ShieldOff, Plus } from 'lucide-react';
import { DataTable } from '@/shared/components/ui/DataTable';
import type { DataTableColumn } from '@/shared/components/ui/DataTable';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useNotifications } from '@/shared/hooks/useNotifications';
import {
  useAgentIdentities,
  useRotateIdentity,
  useRevokeIdentity,
} from '../api/securityExtApi';
import type { AgentIdentity, IdentityStatus, IdentityFilterParams } from '../types/security';
import { AgentIdentityPanel } from './AgentIdentityPanel';

const STATUS_VARIANTS: Record<IdentityStatus, 'success' | 'warning' | 'danger' | 'default'> = {
  active: 'success',
  rotated: 'warning',
  revoked: 'danger',
  expired: 'default',
};

const STATUS_OPTIONS: IdentityStatus[] = ['active', 'rotated', 'revoked', 'expired'];

interface AgentIdentityListProps {
  onProvision: () => void;
}

export const AgentIdentityList: React.FC<AgentIdentityListProps> = ({ onProvision }) => {
  const { hasPermission } = usePermissions();
  const { addNotification } = useNotifications();
  const [filters, setFilters] = useState<IdentityFilterParams>({ page: 1, per_page: 20 });
  const [statusFilter, setStatusFilter] = useState<IdentityStatus | undefined>();
  const [agentIdFilter, setAgentIdFilter] = useState('');
  const [selectedId, setSelectedId] = useState<string | null>(null);

  const canManage = hasPermission('ai.security.manage');

  const effectiveFilters: IdentityFilterParams = {
    ...filters,
    ...(statusFilter ? { status: statusFilter } : {}),
    ...(agentIdFilter ? { agent_id: agentIdFilter } : {}),
  };

  const { data, isLoading } = useAgentIdentities(effectiveFilters);
  const rotateIdentity = useRotateIdentity();
  const revokeIdentity = useRevokeIdentity();

  const identities = data?.items || [];
  const pagination = data?.pagination;

  const handleRotate = (id: string) => {
    rotateIdentity.mutate(id, {
      onSuccess: () => {
        addNotification({ type: 'success', message: 'Identity key rotated successfully' });
      },
      onError: () => {
        addNotification({ type: 'error', message: 'Failed to rotate identity key' });
      },
    });
  };

  const handleRevoke = (id: string) => {
    revokeIdentity.mutate({ id, reason: 'Manual revocation from dashboard' }, {
      onSuccess: () => {
        addNotification({ type: 'success', message: 'Identity revoked successfully' });
      },
      onError: () => {
        addNotification({ type: 'error', message: 'Failed to revoke identity' });
      },
    });
  };

  const columns: DataTableColumn<AgentIdentity>[] = [
    {
      key: 'key_fingerprint',
      header: 'Fingerprint',
      width: '200px',
      render: (item) => (
        <span className="text-theme-primary font-mono text-xs truncate max-w-[180px] block">
          {item.key_fingerprint}
        </span>
      ),
    },
    {
      key: 'agent_id',
      header: 'Agent',
      width: '160px',
      render: (item) => (
        <span className="text-theme-secondary text-sm truncate max-w-[140px] block">
          {item.agent_id}
        </span>
      ),
    },
    {
      key: 'algorithm',
      header: 'Algorithm',
      width: '100px',
      render: (item) => (
        <span className="text-theme-secondary text-sm">{item.algorithm}</span>
      ),
    },
    {
      key: 'status',
      header: 'Status',
      width: '100px',
      render: (item) => (
        <Badge variant={STATUS_VARIANTS[item.status] || 'default'} size="xs">
          {item.status}
        </Badge>
      ),
    },
    {
      key: 'expires_at',
      header: 'Expires',
      width: '160px',
      render: (item) => (
        <span className="text-theme-secondary text-xs">
          {item.expires_at ? new Date(item.expires_at).toLocaleDateString() : 'Never'}
        </span>
      ),
    },
    {
      key: 'created_at',
      header: 'Created',
      width: '160px',
      render: (item) => (
        <span className="text-theme-secondary text-xs">
          {new Date(item.created_at).toLocaleString()}
        </span>
      ),
    },
    {
      key: 'actions',
      header: '',
      width: '100px',
      render: (item) => {
        if (!canManage || item.status === 'revoked') return null;
        return (
          <div className="flex items-center gap-1">
            {item.status === 'active' && (
              <Button
                variant="ghost"
                size="xs"
                onClick={(e) => { e.stopPropagation(); handleRotate(item.id); }}
                loading={rotateIdentity.isPending}
                title="Rotate Key"
              >
                <RotateCw className="h-3.5 w-3.5" />
              </Button>
            )}
            {item.status !== 'expired' && (
              <Button
                variant="ghost"
                size="xs"
                onClick={(e) => { e.stopPropagation(); handleRevoke(item.id); }}
                loading={revokeIdentity.isPending}
                title="Revoke"
              >
                <ShieldOff className="h-3.5 w-3.5 text-theme-error" />
              </Button>
            )}
          </div>
        );
      },
    },
  ];

  return (
    <div className="space-y-4">
      {/* Filters Row */}
      <div className="flex flex-wrap items-center gap-4">
        {/* Status Filter */}
        <div className="flex flex-wrap items-center gap-2">
          <span className="text-xs text-theme-secondary font-medium">Status:</span>
          <Button
            variant={statusFilter === undefined ? 'primary' : 'outline'}
            size="xs"
            onClick={() => { setStatusFilter(undefined); setFilters((prev) => ({ ...prev, page: 1 })); }}
          >
            All
          </Button>
          {STATUS_OPTIONS.map((status) => (
            <Button
              key={status}
              variant={statusFilter === status ? 'primary' : 'outline'}
              size="xs"
              onClick={() => { setStatusFilter(status); setFilters((prev) => ({ ...prev, page: 1 })); }}
            >
              {status}
            </Button>
          ))}
        </div>

        {/* Agent ID Filter */}
        <div className="flex items-center gap-2">
          <span className="text-xs text-theme-secondary font-medium">Agent:</span>
          <input
            type="text"
            value={agentIdFilter}
            onChange={(e) => { setAgentIdFilter(e.target.value); setFilters((prev) => ({ ...prev, page: 1 })); }}
            placeholder="Filter by agent ID..."
            className="text-sm px-2 py-1 rounded border border-theme bg-theme-bg text-theme-primary placeholder:text-theme-muted w-48"
          />
        </div>

        {/* Provision Button */}
        {canManage && (
          <div className="ml-auto">
            <Button variant="primary" size="xs" onClick={onProvision}>
              <Plus className="h-3.5 w-3.5 mr-1" />
              Provision Identity
            </Button>
          </div>
        )}
      </div>

      {/* Identities Table */}
      <DataTable<AgentIdentity>
        columns={columns}
        data={identities}
        loading={isLoading}
        pagination={pagination}
        onPageChange={(page) => setFilters((prev) => ({ ...prev, page }))}
        onRowClick={(item) => setSelectedId(item.id === selectedId ? null : item.id)}
        emptyState={{
          icon: Key,
          title: 'No agent identities found',
          description: 'No identities match the current filters. Provision a new identity to get started.',
        }}
      />

      {/* Detail Panel */}
      {selectedId && (
        <AgentIdentityPanel
          identityId={selectedId}
          onClose={() => setSelectedId(null)}
        />
      )}
    </div>
  );
};

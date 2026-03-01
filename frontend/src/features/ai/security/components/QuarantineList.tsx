import React, { useState } from 'react';
import { ShieldAlert, ArrowUpCircle, RotateCcw } from 'lucide-react';
import { DataTable } from '@/shared/components/ui/DataTable';
import type { DataTableColumn } from '@/shared/components/ui/DataTable';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useNotifications } from '@/shared/hooks/useNotifications';
import {
  useQuarantineRecords,
  useEscalateQuarantine,
  useRestoreQuarantine,
} from '../api/securityExtApi';
import type {
  QuarantineRecord,
  QuarantineSeverity,
  QuarantineStatus,
  QuarantineFilterParams,
} from '../types/security';
import { QuarantineDetailPanel } from './QuarantineDetailPanel';

const SEVERITY_VARIANTS: Record<QuarantineSeverity, 'danger' | 'warning' | 'info' | 'default'> = {
  critical: 'danger',
  high: 'warning',
  medium: 'default',
  low: 'info',
};

const STATUS_VARIANTS: Record<QuarantineStatus, 'danger' | 'success' | 'default'> = {
  active: 'danger',
  restored: 'success',
  expired: 'default',
};

const SEVERITY_OPTIONS: QuarantineSeverity[] = ['critical', 'high', 'medium', 'low'];
const STATUS_OPTIONS: QuarantineStatus[] = ['active', 'restored', 'expired'];

const ESCALATION_MAP: Record<string, string> = {
  low: 'medium',
  medium: 'high',
  high: 'critical',
};

export const QuarantineList: React.FC = () => {
  const { hasPermission } = usePermissions();
  const { addNotification } = useNotifications();
  const [filters, setFilters] = useState<QuarantineFilterParams>({ page: 1, per_page: 20 });
  const [severityFilter, setSeverityFilter] = useState<QuarantineSeverity | undefined>();
  const [statusFilter, setStatusFilter] = useState<QuarantineStatus | undefined>();
  const [selectedId, setSelectedId] = useState<string | null>(null);

  const canManage = hasPermission('ai.security.manage');

  const effectiveFilters: QuarantineFilterParams = {
    ...filters,
    ...(severityFilter ? { severity: severityFilter } : {}),
    ...(statusFilter ? { status: statusFilter } : {}),
  };

  const { data, isLoading } = useQuarantineRecords(effectiveFilters);
  const escalateQuarantine = useEscalateQuarantine();
  const restoreQuarantine = useRestoreQuarantine();

  const records = data?.items || [];
  const pagination = data?.pagination;

  const handleEscalate = (record: QuarantineRecord) => {
    const nextSeverity = ESCALATION_MAP[record.severity];
    if (!nextSeverity) return;

    escalateQuarantine.mutate({ id: record.id, new_severity: nextSeverity }, {
      onSuccess: () => {
        addNotification({ type: 'success', message: `Quarantine escalated to ${nextSeverity}` });
      },
      onError: () => {
        addNotification({ type: 'error', message: 'Failed to escalate quarantine' });
      },
    });
  };

  const handleRestore = (id: string) => {
    restoreQuarantine.mutate(id, {
      onSuccess: () => {
        addNotification({ type: 'success', message: 'Agent restored from quarantine' });
      },
      onError: () => {
        addNotification({ type: 'error', message: 'Failed to restore agent' });
      },
    });
  };

  const columns: DataTableColumn<QuarantineRecord>[] = [
    {
      key: 'severity',
      header: 'Severity',
      width: '100px',
      render: (item) => (
        <Badge variant={SEVERITY_VARIANTS[item.severity]} size="xs">
          {item.severity}
        </Badge>
      ),
    },
    {
      key: 'agent_id',
      header: 'Agent',
      width: '160px',
      render: (item) => (
        <span className="text-theme-primary text-sm truncate max-w-[140px] block">
          {item.agent_id}
        </span>
      ),
    },
    {
      key: 'trigger_reason',
      header: 'Reason',
      render: (item) => (
        <span className="text-theme-secondary text-sm truncate max-w-xs block">
          {item.trigger_reason}
        </span>
      ),
    },
    {
      key: 'trigger_source',
      header: 'Source',
      width: '120px',
      render: (item) => (
        <span className="text-theme-secondary text-sm">{item.trigger_source}</span>
      ),
    },
    {
      key: 'status',
      header: 'Status',
      width: '100px',
      render: (item) => (
        <Badge variant={STATUS_VARIANTS[item.status]} size="xs">
          {item.status}
        </Badge>
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
        if (!canManage || item.status !== 'active') return null;
        return (
          <div className="flex items-center gap-1">
            {item.severity !== 'critical' && (
              <Button
                variant="ghost"
                size="xs"
                onClick={(e) => { e.stopPropagation(); handleEscalate(item); }}
                loading={escalateQuarantine.isPending}
                title="Escalate"
              >
                <ArrowUpCircle className="h-3.5 w-3.5 text-theme-warning" />
              </Button>
            )}
            <Button
              variant="ghost"
              size="xs"
              onClick={(e) => { e.stopPropagation(); handleRestore(item.id); }}
              loading={restoreQuarantine.isPending}
              title="Restore"
            >
              <RotateCcw className="h-3.5 w-3.5 text-theme-success" />
            </Button>
          </div>
        );
      },
    },
  ];

  return (
    <div className="space-y-4">
      {/* Filters Row */}
      <div className="flex flex-wrap items-center gap-4">
        {/* Severity Filter */}
        <div className="flex flex-wrap items-center gap-2">
          <span className="text-xs text-theme-secondary font-medium">Severity:</span>
          <Button
            variant={severityFilter === undefined ? 'primary' : 'outline'}
            size="xs"
            onClick={() => { setSeverityFilter(undefined); setFilters((prev) => ({ ...prev, page: 1 })); }}
          >
            All
          </Button>
          {SEVERITY_OPTIONS.map((sev) => (
            <Button
              key={sev}
              variant={severityFilter === sev ? 'primary' : 'outline'}
              size="xs"
              onClick={() => { setSeverityFilter(sev); setFilters((prev) => ({ ...prev, page: 1 })); }}
            >
              {sev}
            </Button>
          ))}
        </div>

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
      </div>

      {/* Quarantine Table */}
      <DataTable<QuarantineRecord>
        columns={columns}
        data={records}
        loading={isLoading}
        pagination={pagination}
        onPageChange={(page) => setFilters((prev) => ({ ...prev, page }))}
        onRowClick={(item) => setSelectedId(item.id === selectedId ? null : item.id)}
        emptyState={{
          icon: ShieldAlert,
          title: 'No quarantine records found',
          description: 'No quarantine records match the current filters.',
        }}
      />

      {/* Detail Panel */}
      {selectedId && (
        <QuarantineDetailPanel
          recordId={selectedId}
          onClose={() => setSelectedId(null)}
        />
      )}
    </div>
  );
};

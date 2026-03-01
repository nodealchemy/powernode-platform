import React, { useState } from 'react';
import { AlertTriangle, ChevronDown, ChevronRight, CheckCircle } from 'lucide-react';
import { DataTable } from '@/shared/components/ui/DataTable';
import type { DataTableColumn } from '@/shared/components/ui/DataTable';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useViolations, useResolveViolation } from '../api/auditApi';
import type { PolicyViolation, ViolationSeverity, ViolationStatus, ViolationFilterParams } from '../types/audit';

const SEVERITY_VARIANTS: Record<ViolationSeverity, 'danger' | 'warning' | 'info' | 'default'> = {
  critical: 'danger',
  high: 'warning',
  medium: 'default',
  low: 'info',
};

const STATUS_VARIANTS: Record<ViolationStatus, 'danger' | 'warning' | 'info' | 'success' | 'default' | 'secondary'> = {
  open: 'danger',
  acknowledged: 'warning',
  investigating: 'info',
  resolved: 'success',
  dismissed: 'secondary',
  escalated: 'danger',
};

const STATUS_OPTIONS: ViolationStatus[] = ['open', 'acknowledged', 'investigating', 'resolved', 'dismissed', 'escalated'];

export const ViolationList: React.FC = () => {
  const { hasPermission } = usePermissions();
  const { addNotification } = useNotifications();
  const [filters, setFilters] = useState<ViolationFilterParams>({ page: 1, per_page: 20 });
  const [expandedId, setExpandedId] = useState<string | null>(null);

  const { data, isLoading } = useViolations(filters);
  const resolveViolation = useResolveViolation();

  const canResolve = hasPermission('ai.audits.manage');

  const handleStatusFilter = (status: ViolationStatus | undefined) => {
    setFilters((prev) => ({ ...prev, status, page: 1 }));
  };

  const handleResolve = (violationId: string) => {
    resolveViolation.mutate(violationId, {
      onSuccess: () => {
        addNotification({ type: 'success', message: 'Violation resolved successfully' });
      },
      onError: () => {
        addNotification({ type: 'error', message: 'Failed to resolve violation' });
      },
    });
  };

  const handleRowClick = (item: PolicyViolation) => {
    setExpandedId((prev) => (prev === item.id ? null : item.id));
  };

  const columns: DataTableColumn<PolicyViolation>[] = [
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
      key: 'description',
      header: 'Description',
      render: (item) => (
        <div className="flex items-center gap-2">
          {expandedId === item.id ? (
            <ChevronDown className="h-4 w-4 text-theme-muted flex-shrink-0" />
          ) : (
            <ChevronRight className="h-4 w-4 text-theme-muted flex-shrink-0" />
          )}
          <span className="text-theme-primary truncate max-w-xs">{item.description}</span>
        </div>
      ),
    },
    {
      key: 'policy_name',
      header: 'Policy',
      render: (item) => (
        <span className="text-theme-secondary">{item.policy_name || '--'}</span>
      ),
    },
    {
      key: 'status',
      header: 'Status',
      width: '130px',
      render: (item) => (
        <Badge variant={STATUS_VARIANTS[item.status]} size="xs">
          {item.status}
        </Badge>
      ),
    },
    {
      key: 'detected_at',
      header: 'Detected',
      width: '160px',
      render: (item) => (
        <span className="text-theme-secondary text-xs">
          {new Date(item.detected_at).toLocaleString()}
        </span>
      ),
    },
    {
      key: 'actions',
      header: '',
      width: '80px',
      render: (item) => {
        if (!canResolve || item.status === 'resolved' || item.status === 'dismissed') return null;
        return (
          <Button
            variant="ghost"
            size="xs"
            onClick={(e) => {
              e.stopPropagation();
              handleResolve(item.id);
            }}
            loading={resolveViolation.isPending}
            title="Resolve"
          >
            <CheckCircle className="h-4 w-4" />
          </Button>
        );
      },
    },
  ];

  const violations = data?.data || [];
  const pagination = data?.pagination;

  return (
    <div className="space-y-4">
      {/* Status Filters */}
      <div className="flex flex-wrap items-center gap-2">
        <Button
          variant={filters.status === undefined ? 'primary' : 'outline'}
          size="xs"
          onClick={() => handleStatusFilter(undefined)}
        >
          All
        </Button>
        {STATUS_OPTIONS.map((status) => (
          <Button
            key={status}
            variant={filters.status === status ? 'primary' : 'outline'}
            size="xs"
            onClick={() => handleStatusFilter(status)}
          >
            {status}
          </Button>
        ))}
      </div>

      {/* Violations Table */}
      <DataTable<PolicyViolation>
        columns={columns}
        data={violations}
        loading={isLoading}
        pagination={pagination}
        onPageChange={(page) => setFilters((prev) => ({ ...prev, page }))}
        onRowClick={handleRowClick}
        emptyState={{
          icon: AlertTriangle,
          title: 'No violations found',
          description: 'No policy violations match the current filters.',
        }}
      />

      {/* Expanded Detail */}
      {expandedId && (() => {
        const expanded = violations.find((v) => v.id === expandedId);
        if (!expanded || expanded.remediation_steps.length === 0) return null;
        return (
          <div className="bg-theme-surface border border-theme rounded-lg p-4 space-y-2">
            <h4 className="text-sm font-medium text-theme-primary">Remediation Steps</h4>
            <ul className="list-disc list-inside space-y-1">
              {expanded.remediation_steps.map((step, idx) => (
                <li key={idx} className="text-sm text-theme-secondary">{step}</li>
              ))}
            </ul>
            {expanded.resolved_at && (
              <p className="text-xs text-theme-muted">
                Resolved at: {new Date(expanded.resolved_at).toLocaleString()}
              </p>
            )}
          </div>
        );
      })()}
    </div>
  );
};

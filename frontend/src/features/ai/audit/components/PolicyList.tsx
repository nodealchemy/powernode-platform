import React, { useState } from 'react';
import { FileCheck, ToggleLeft, ToggleRight } from 'lucide-react';
import { DataTable } from '@/shared/components/ui/DataTable';
import type { DataTableColumn } from '@/shared/components/ui/DataTable';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { usePolicies, useTogglePolicy } from '../api/auditApi';
import type { CompliancePolicy, PolicyFilterParams, PolicyStatus } from '../types/audit';

const STATUS_VARIANTS: Record<PolicyStatus, 'success' | 'warning' | 'default' | 'secondary'> = {
  active: 'success',
  draft: 'default',
  disabled: 'secondary',
  archived: 'secondary',
};

const ENFORCEMENT_VARIANTS: Record<string, 'info' | 'warning' | 'danger' | 'default'> = {
  log: 'info',
  warn: 'warning',
  block: 'danger',
  require_approval: 'default',
};

export const PolicyList: React.FC = () => {
  const { hasPermission } = usePermissions();
  const { addNotification } = useNotifications();
  const [filters, setFilters] = useState<PolicyFilterParams>({ page: 1, per_page: 20 });
  const [typeFilter, setTypeFilter] = useState<string | undefined>();

  const { data, isLoading } = usePolicies({ ...filters, policy_type: typeFilter });
  const togglePolicy = useTogglePolicy();

  const canManage = hasPermission('ai.audits.manage');

  const handleToggle = (policyId: string) => {
    togglePolicy.mutate(policyId, {
      onSuccess: () => {
        addNotification({ type: 'success', message: 'Policy status toggled' });
      },
      onError: () => {
        addNotification({ type: 'error', message: 'Failed to toggle policy' });
      },
    });
  };

  // Derive unique policy types from data for filter buttons
  const policies = data?.data || [];
  const pagination = data?.pagination;
  const policyTypes = Array.from(new Set(policies.map((p) => p.policy_type))).sort();

  const columns: DataTableColumn<CompliancePolicy>[] = [
    {
      key: 'name',
      header: 'Name',
      render: (item) => (
        <div>
          <span className="text-theme-primary font-medium">{item.name}</span>
          {item.is_system && (
            <Badge variant="secondary" size="xs" className="ml-2">system</Badge>
          )}
          {item.is_required && (
            <Badge variant="warning" size="xs" className="ml-1">required</Badge>
          )}
        </div>
      ),
    },
    {
      key: 'policy_type',
      header: 'Type',
      width: '120px',
      render: (item) => (
        <Badge variant="info" size="xs">{item.policy_type}</Badge>
      ),
    },
    {
      key: 'enforcement_level',
      header: 'Enforcement',
      width: '140px',
      render: (item) => (
        <Badge variant={ENFORCEMENT_VARIANTS[item.enforcement_level] || 'default'} size="xs">
          {item.enforcement_level}
        </Badge>
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
      key: 'violation_count',
      header: 'Violations',
      width: '100px',
      render: (item) => (
        <span className={`font-medium ${item.violation_count > 0 ? 'text-theme-error' : 'text-theme-secondary'}`}>
          {item.violation_count}
        </span>
      ),
    },
    {
      key: 'priority',
      header: 'Priority',
      width: '80px',
      render: (item) => (
        <span className="text-theme-secondary">{item.priority}</span>
      ),
    },
    {
      key: 'actions',
      header: '',
      width: '80px',
      render: (item) => {
        if (!canManage || item.is_required) return null;
        const isActive = item.status === 'active';
        return (
          <Button
            variant="ghost"
            size="xs"
            onClick={(e) => {
              e.stopPropagation();
              handleToggle(item.id);
            }}
            loading={togglePolicy.isPending}
            title={isActive ? 'Disable policy' : 'Enable policy'}
          >
            {isActive ? (
              <ToggleRight className="h-4 w-4 text-theme-success" />
            ) : (
              <ToggleLeft className="h-4 w-4 text-theme-muted" />
            )}
          </Button>
        );
      },
    },
  ];

  return (
    <div className="space-y-4">
      {/* Type Filters */}
      {policyTypes.length > 0 && (
        <div className="flex flex-wrap items-center gap-2">
          <Button
            variant={typeFilter === undefined ? 'primary' : 'outline'}
            size="xs"
            onClick={() => { setTypeFilter(undefined); setFilters((prev) => ({ ...prev, page: 1 })); }}
          >
            All
          </Button>
          {policyTypes.map((type) => (
            <Button
              key={type}
              variant={typeFilter === type ? 'primary' : 'outline'}
              size="xs"
              onClick={() => { setTypeFilter(type); setFilters((prev) => ({ ...prev, page: 1 })); }}
            >
              {type}
            </Button>
          ))}
        </div>
      )}

      {/* Policies Table */}
      <DataTable<CompliancePolicy>
        columns={columns}
        data={policies}
        loading={isLoading}
        pagination={pagination}
        onPageChange={(page) => setFilters((prev) => ({ ...prev, page }))}
        emptyState={{
          icon: FileCheck,
          title: 'No policies found',
          description: 'No compliance policies match the current filters.',
        }}
      />
    </div>
  );
};

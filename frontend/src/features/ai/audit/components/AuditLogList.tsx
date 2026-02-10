import React, { useState } from 'react';
import { Activity } from 'lucide-react';
import { DataTable } from '@/shared/components/ui/DataTable';
import type { DataTableColumn } from '@/shared/components/ui/DataTable';
import { Badge } from '@/shared/components/ui/Badge';
import { useAuditEntries } from '../api/auditApi';
import type { AuditEntry, AuditOutcome, AuditEntryFilterParams } from '../types/audit';

const OUTCOME_VARIANTS: Record<AuditOutcome, 'success' | 'danger' | 'warning' | 'default'> = {
  success: 'success',
  failure: 'danger',
  blocked: 'warning',
  warning: 'warning',
};

export const AuditLogList: React.FC = () => {
  const [filters, setFilters] = useState<AuditEntryFilterParams>({ page: 1, per_page: 20 });
  const [startDate, setStartDate] = useState('');
  const [endDate, setEndDate] = useState('');

  const effectiveFilters: AuditEntryFilterParams = {
    ...filters,
    ...(startDate ? { start_date: startDate } : {}),
    ...(endDate ? { end_date: endDate } : {}),
  };

  const { data, isLoading } = useAuditEntries(effectiveFilters);

  const entries = data?.data || [];
  const pagination = data?.pagination;

  const handleDateApply = () => {
    setFilters((prev) => ({ ...prev, page: 1 }));
  };

  const columns: DataTableColumn<AuditEntry>[] = [
    {
      key: 'occurred_at',
      header: 'Timestamp',
      width: '170px',
      render: (item) => (
        <span className="text-theme-secondary text-xs">
          {new Date(item.occurred_at).toLocaleString()}
        </span>
      ),
    },
    {
      key: 'action_type',
      header: 'Action',
      width: '140px',
      render: (item) => (
        <span className="text-theme-primary font-medium text-sm">{item.action_type}</span>
      ),
    },
    {
      key: 'resource_type',
      header: 'Resource',
      width: '130px',
      render: (item) => (
        <span className="text-theme-secondary text-sm">{item.resource_type}</span>
      ),
    },
    {
      key: 'outcome',
      header: 'Outcome',
      width: '100px',
      render: (item) => (
        <Badge variant={OUTCOME_VARIANTS[item.outcome]} size="xs">
          {item.outcome}
        </Badge>
      ),
    },
    {
      key: 'user_name',
      header: 'User',
      width: '130px',
      render: (item) => (
        <span className="text-theme-secondary text-sm">{item.user_name || '--'}</span>
      ),
    },
    {
      key: 'description',
      header: 'Description',
      render: (item) => (
        <span className="text-theme-secondary text-sm truncate max-w-xs block">
          {item.description || '--'}
        </span>
      ),
    },
  ];

  return (
    <div className="space-y-4">
      {/* Date Range Filter */}
      <div className="flex flex-wrap items-end gap-3">
        <div>
          <label className="block text-xs text-theme-secondary mb-1">Start Date</label>
          <input
            type="date"
            value={startDate}
            onChange={(e) => setStartDate(e.target.value)}
            className="px-3 py-1.5 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-1 focus:ring-theme-interactive-primary"
          />
        </div>
        <div>
          <label className="block text-xs text-theme-secondary mb-1">End Date</label>
          <input
            type="date"
            value={endDate}
            onChange={(e) => setEndDate(e.target.value)}
            className="px-3 py-1.5 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-1 focus:ring-theme-interactive-primary"
          />
        </div>
        <button
          onClick={handleDateApply}
          className="btn-theme btn-theme-outline btn-theme-sm"
        >
          Apply
        </button>
        {(startDate || endDate) && (
          <button
            onClick={() => {
              setStartDate('');
              setEndDate('');
              setFilters((prev) => ({ ...prev, page: 1 }));
            }}
            className="btn-theme btn-theme-ghost btn-theme-sm"
          >
            Clear
          </button>
        )}
      </div>

      {/* Audit Entries Table */}
      <DataTable<AuditEntry>
        columns={columns}
        data={entries}
        loading={isLoading}
        pagination={pagination}
        onPageChange={(page) => setFilters((prev) => ({ ...prev, page }))}
        emptyState={{
          icon: Activity,
          title: 'No audit entries found',
          description: 'No audit log entries match the current filters.',
        }}
      />
    </div>
  );
};

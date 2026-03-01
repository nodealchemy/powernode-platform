import React, { useState } from 'react';
import { Eye } from 'lucide-react';
import { DataTable } from '@/shared/components/ui/DataTable';
import type { DataTableColumn } from '@/shared/components/ui/DataTable';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { useSecurityEvents } from '../api/auditApi';
import type { SecurityEvent, SecurityEventFilterParams } from '../types/audit';

const SEVERITY_VARIANTS: Record<string, 'danger' | 'warning' | 'info' | 'default'> = {
  critical: 'danger',
  high: 'warning',
  medium: 'default',
  low: 'info',
};

const RISK_VARIANTS: Record<string, 'danger' | 'warning' | 'info' | 'default'> = {
  critical: 'danger',
  high: 'danger',
  elevated: 'warning',
  medium: 'warning',
  low: 'info',
  minimal: 'default',
};

const SEVERITY_OPTIONS = ['critical', 'high', 'medium', 'low'];
const RISK_OPTIONS = ['critical', 'high', 'elevated', 'medium', 'low', 'minimal'];

export const SecurityEventList: React.FC = () => {
  const [filters, setFilters] = useState<SecurityEventFilterParams>({ page: 1, per_page: 20 });
  const [severityFilter, setSeverityFilter] = useState<string | undefined>();
  const [riskFilter, setRiskFilter] = useState<string | undefined>();

  const effectiveFilters: SecurityEventFilterParams = {
    ...filters,
    ...(severityFilter ? { severity: severityFilter } : {}),
    ...(riskFilter ? { risk_level: riskFilter } : {}),
  };

  const { data, isLoading } = useSecurityEvents(effectiveFilters);

  const events = data?.data || [];
  const pagination = data?.pagination;

  const columns: DataTableColumn<SecurityEvent>[] = [
    {
      key: 'created_at',
      header: 'Timestamp',
      width: '170px',
      render: (item) => (
        <span className="text-theme-secondary text-xs">
          {new Date(item.created_at).toLocaleString()}
        </span>
      ),
    },
    {
      key: 'action',
      header: 'Action',
      width: '150px',
      render: (item) => (
        <span className="text-theme-primary font-medium text-sm">{item.action}</span>
      ),
    },
    {
      key: 'resource_type',
      header: 'Resource',
      width: '120px',
      render: (item) => (
        <span className="text-theme-secondary text-sm">{item.resource_type}</span>
      ),
    },
    {
      key: 'severity',
      header: 'Severity',
      width: '100px',
      render: (item) => (
        <Badge variant={SEVERITY_VARIANTS[item.severity] || 'default'} size="xs">
          {item.severity}
        </Badge>
      ),
    },
    {
      key: 'risk_level',
      header: 'Risk Level',
      width: '110px',
      render: (item) => (
        <Badge variant={RISK_VARIANTS[item.risk_level] || 'default'} size="xs">
          {item.risk_level}
        </Badge>
      ),
    },
    {
      key: 'source',
      header: 'Source',
      width: '120px',
      render: (item) => (
        <span className="text-theme-secondary text-sm">{item.source}</span>
      ),
    },
    {
      key: 'ip_address',
      header: 'IP Address',
      width: '130px',
      render: (item) => (
        <span className="text-theme-muted text-xs font-mono">{item.ip_address || '--'}</span>
      ),
    },
  ];

  return (
    <div className="space-y-4">
      {/* Filters */}
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

        {/* Risk Level Filter */}
        <div className="flex flex-wrap items-center gap-2">
          <span className="text-xs text-theme-secondary font-medium">Risk:</span>
          <Button
            variant={riskFilter === undefined ? 'primary' : 'outline'}
            size="xs"
            onClick={() => { setRiskFilter(undefined); setFilters((prev) => ({ ...prev, page: 1 })); }}
          >
            All
          </Button>
          {RISK_OPTIONS.map((risk) => (
            <Button
              key={risk}
              variant={riskFilter === risk ? 'primary' : 'outline'}
              size="xs"
              onClick={() => { setRiskFilter(risk); setFilters((prev) => ({ ...prev, page: 1 })); }}
            >
              {risk}
            </Button>
          ))}
        </div>
      </div>

      {/* Security Events Table */}
      <DataTable<SecurityEvent>
        columns={columns}
        data={events}
        loading={isLoading}
        pagination={pagination}
        onPageChange={(page) => setFilters((prev) => ({ ...prev, page }))}
        emptyState={{
          icon: Eye,
          title: 'No security events found',
          description: 'No security events match the current filters.',
        }}
      />
    </div>
  );
};

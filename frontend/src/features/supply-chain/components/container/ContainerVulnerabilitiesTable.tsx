import React from 'react';
import { ExternalLink, AlertTriangle } from 'lucide-react';
import { DataTable, DataTableColumn } from '@/shared/components/ui/DataTable';
import { Badge } from '@/shared/components/ui/Badge';

type Severity = 'critical' | 'high' | 'medium' | 'low';

interface ContainerVulnerability {
  id: string;
  vulnerability_id: string;
  severity: Severity;
  cvss_score: number;
  package_name: string;
  package_version: string;
  fixed_version?: string;
  description?: string;
  published_at?: string;
  exploit_available?: boolean;
}

interface Pagination {
  current_page: number;
  per_page: number;
  total_pages: number;
  total_count: number;
}

interface ContainerVulnerabilitiesTableProps {
  vulnerabilities: ContainerVulnerability[];
  loading: boolean;
  pagination?: Pagination;
  onPageChange?: (page: number) => void;
}

const severityStyles: Record<Severity, string> = {
  critical: 'bg-theme-error text-white',
  high: 'bg-theme-error/80 text-white',
  medium: 'bg-theme-warning text-theme-on-warning',
  low: 'bg-theme-info text-white',
};

export const ContainerVulnerabilitiesTable: React.FC<ContainerVulnerabilitiesTableProps> = ({
  vulnerabilities,
  loading,
  pagination,
  onPageChange,
}) => {
  const columns: DataTableColumn<ContainerVulnerability>[] = [
    {
      key: 'vulnerability_id',
      header: 'Vulnerability',
      render: (item) => (
        <a
          href={`https://nvd.nist.gov/vuln/detail/${item.vulnerability_id}`}
          target="_blank"
          rel="noopener noreferrer"
          className="flex items-center gap-1 text-theme-interactive-primary hover:underline font-medium"
        >
          {item.vulnerability_id}
          <ExternalLink className="w-3 h-3" />
        </a>
      ),
    },
    {
      key: 'severity',
      header: 'Severity',
      render: (item) => (
        <Badge className={severityStyles[item.severity]} size="sm">
          {item.severity.toUpperCase()}
        </Badge>
      ),
    },
    {
      key: 'cvss_score',
      header: 'CVSS',
      render: (item) => (
        <span className="font-mono text-sm text-theme-primary">{item.cvss_score.toFixed(1)}</span>
      ),
    },
    {
      key: 'package',
      header: 'Package',
      render: (item) => (
        <div>
          <p className="font-medium text-theme-primary">{item.package_name}</p>
          <p className="text-xs text-theme-secondary">{item.package_version}</p>
        </div>
      ),
    },
    {
      key: 'fixed_version',
      header: 'Fixed In',
      render: (item) => (
        <span className={item.fixed_version ? 'text-theme-success' : 'text-theme-muted'}>
          {item.fixed_version || 'No fix available'}
        </span>
      ),
    },
    {
      key: 'exploit',
      header: 'Exploit',
      render: (item) =>
        item.exploit_available ? (
          <Badge variant="danger" size="sm">
            Available
          </Badge>
        ) : (
          <span className="text-theme-muted text-sm">-</span>
        ),
    },
  ];

  return (
    <DataTable
      columns={columns}
      data={vulnerabilities}
      loading={loading}
      pagination={pagination}
      onPageChange={onPageChange}
      emptyState={{
        icon: AlertTriangle,
        title: 'No vulnerabilities found',
        description: 'This container image has no detected vulnerabilities.',
      }}
    />
  );
};

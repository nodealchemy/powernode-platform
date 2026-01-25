import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { DataTable } from '@/shared/components/ui/DataTable';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { AlertTriangle, CheckCircle2, ShieldAlert, Eye } from 'lucide-react';
import { useLicenseViolations, useResolveViolation, useGrantViolationException } from '../hooks/useLicenseCompliance';
import { SeverityBadge } from '../components/shared/SeverityBadge';
import type { LicenseViolation } from '../types/license';

type ViolationStatus = 'open' | 'resolved' | 'exception_granted';

export const LicenseViolationsPage: React.FC = () => {
  const navigate = useNavigate();
  const [currentPage, setCurrentPage] = useState(1);
  const [activeTab, setActiveTab] = useState<ViolationStatus>('open');
  const perPage = 25;

  const { data, isLoading } = useLicenseViolations({
    page: currentPage,
    per_page: perPage,
    status: activeTab,
  });

  const resolveMutation = useResolveViolation();
  const grantExceptionMutation = useGrantViolationException();

  const handleResolve = async (id: string) => {
    const note = window.prompt('Enter resolution note (optional):');
    if (note !== null) {
      await resolveMutation.mutateAsync({ id, note: note || undefined });
    }
  };

  const handleGrantException = async (id: string) => {
    const note = window.prompt('Enter exception justification (required):');
    if (note && note.trim()) {
      await grantExceptionMutation.mutateAsync({ id, note });
    } else if (note !== null) {
      alert('Exception justification is required');
    }
  };

  const getViolationTypeBadge = (type: string) => {
    const variants: Record<string, 'danger' | 'warning' | 'info'> = {
      denied: 'danger',
      copyleft_contamination: 'warning',
      incompatible: 'warning',
      unknown_license: 'info',
    };
    const labels: Record<string, string> = {
      denied: 'Denied',
      copyleft_contamination: 'Copyleft',
      incompatible: 'Incompatible',
      unknown_license: 'Unknown',
    };
    return <Badge variant={variants[type] || 'default'}>{labels[type] || type}</Badge>;
  };

  const getStatusBadge = (status: string) => {
    const variants: Record<string, 'success' | 'warning' | 'info'> = {
      open: 'warning',
      resolved: 'success',
      exception_granted: 'info',
    };
    const labels: Record<string, string> = {
      open: 'Open',
      resolved: 'Resolved',
      exception_granted: 'Exception',
    };
    return <Badge variant={variants[status] || 'default'}>{labels[status] || status}</Badge>;
  };

  const columns = [
    {
      key: 'component',
      header: 'Component',
      render: (violation: LicenseViolation) => (
        <div>
          <div className="font-medium text-theme-primary">{violation.component_name}</div>
          <div className="text-sm text-theme-tertiary">{violation.component_version}</div>
        </div>
      ),
    },
    {
      key: 'license',
      header: 'License',
      render: (violation: LicenseViolation) => (
        <div>
          <div className="text-theme-primary">{violation.license_name}</div>
          {violation.license_spdx_id && (
            <div className="text-xs text-theme-tertiary">{violation.license_spdx_id}</div>
          )}
        </div>
      ),
    },
    {
      key: 'violation_type',
      header: 'Type',
      render: (violation: LicenseViolation) => getViolationTypeBadge(violation.violation_type),
    },
    {
      key: 'severity',
      header: 'Severity',
      render: (violation: LicenseViolation) => <SeverityBadge severity={violation.severity} />,
    },
    {
      key: 'status',
      header: 'Status',
      render: (violation: LicenseViolation) => getStatusBadge(violation.status),
    },
    {
      key: 'created_at',
      header: 'Created',
      render: (violation: LicenseViolation) => (
        <span className="text-theme-tertiary">
          {new Date(violation.created_at).toLocaleDateString()}
        </span>
      ),
    },
    {
      key: 'actions',
      header: 'Actions',
      render: (violation: LicenseViolation) => {
        return (
          <div className="flex gap-2 items-center">
            <button
              onClick={() => navigate(`/app/supply-chain/licenses/violations/${violation.id}`)}
              className="text-theme-interactive-primary hover:text-theme-interactive-primary-hover"
              title="View Details"
            >
              <Eye className="w-4 h-4" />
            </button>
            {violation.status === 'open' && (
              <>
                <Button
                  variant="success"
                  size="xs"
                  onClick={() => handleResolve(violation.id)}
                >
                  Resolve
                </Button>
                <Button
                  variant="secondary"
                  size="xs"
                  onClick={() => handleGrantException(violation.id)}
                >
                  Exception
                </Button>
              </>
            )}
            {violation.status !== 'open' && violation.resolved_at && (
              <span className="text-theme-tertiary text-sm">
                {new Date(violation.resolved_at).toLocaleDateString()}
              </span>
            )}
          </div>
        );
      },
    },
  ];

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'Supply Chain', href: '/app/supply-chain' },
    { label: 'License Violations' },
  ];

  const tabs = [
    { id: 'open' as ViolationStatus, label: 'Open', icon: AlertTriangle },
    { id: 'resolved' as ViolationStatus, label: 'Resolved', icon: CheckCircle2 },
    { id: 'exception_granted' as ViolationStatus, label: 'Exception Granted', icon: ShieldAlert },
  ];

  return (
    <PageContainer
      title="License Violations"
      description="Monitor and manage license compliance violations"
      breadcrumbs={breadcrumbs}
    >
      <div className="card-theme-elevated">
        {/* Tabs */}
        <div className="border-b border-theme-border">
          <nav className="-mb-px flex space-x-8 px-6 pt-4">
            {tabs.map((tab) => {
              const Icon = tab.icon;
              return (
                <button
                  key={tab.id}
                  onClick={() => {
                    setActiveTab(tab.id);
                    setCurrentPage(1);
                  }}
                  className={`
                    flex items-center gap-2 whitespace-nowrap py-4 px-1 border-b-2 font-medium text-sm
                    ${
                      activeTab === tab.id
                        ? 'border-theme-interactive-primary text-theme-interactive-primary'
                        : 'border-transparent text-theme-tertiary hover:text-theme-secondary hover:border-theme-border-hover'
                    }
                  `}
                >
                  <Icon className="h-5 w-5" />
                  {tab.label}
                </button>
              );
            })}
          </nav>
        </div>

        {/* Table */}
        <DataTable
          columns={columns}
          data={data?.violations || []}
          loading={isLoading}
          pagination={data?.pagination || undefined}
          onPageChange={setCurrentPage}
          emptyState={{
            icon: AlertTriangle,
            title: `No ${activeTab === 'open' ? 'open' : activeTab === 'resolved' ? 'resolved' : 'exception granted'} violations`,
            description: `There are no ${activeTab === 'open' ? 'open' : activeTab === 'resolved' ? 'resolved' : 'exception granted'} license violations`,
          }}
        />
      </div>
    </PageContainer>
  );
};

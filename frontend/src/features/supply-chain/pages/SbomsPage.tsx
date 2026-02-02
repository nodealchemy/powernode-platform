import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { RefreshCw, FileText, Trash2, CheckCircle, XCircle } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { PageErrorBoundary } from '@/shared/components/error/ErrorBoundary';
import { TabContainer } from '@/shared/components/ui/TabContainer';
import { DataTable } from '@/shared/components/ui/DataTable';
import { Badge } from '@/shared/components/ui/Badge';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { useSboms } from '../hooks/useSboms';
import { sbomsApi } from '../services/sbomsApi';

type SbomStatus = 'draft' | 'generating' | 'completed' | 'failed';

const StatusBadge: React.FC<{ status: SbomStatus }> = ({ status }) => {
  const variants = {
    draft: 'secondary' as const,
    generating: 'warning' as const,
    completed: 'success' as const,
    failed: 'danger' as const,
  };

  return (
    <Badge variant={variants[status]} size="sm">
      {status.charAt(0).toUpperCase() + status.slice(1)}
    </Badge>
  );
};

const FormatBadge: React.FC<{ format: string }> = ({ format }) => (
  <Badge variant="outline" size="sm">
    {format.toUpperCase()}
  </Badge>
);

const RiskScoreBadge: React.FC<{ score: number }> = ({ score }) => {
  const variant = score >= 7 ? 'danger' : score >= 4 ? 'warning' : 'success';
  return (
    <Badge variant={variant} size="sm">
      {score.toFixed(1)}
    </Badge>
  );
};

const SbomsPageContent: React.FC = () => {
  const navigate = useNavigate();
  const { showNotification } = useNotifications();
  const { confirm, ConfirmationDialog } = useConfirmation();
  const [statusFilter, setStatusFilter] = useState<SbomStatus | ''>('');
  const [page, setPage] = useState(1);

  const { sboms, pagination, loading, refresh } = useSboms({
    page,
    perPage: 20,
    status: statusFilter || undefined,
  });

  const handleDelete = async (id: string, name: string) => {
    confirm({
      title: 'Delete SBOM',
      message: `Are you sure you want to delete "${name}"?`,
      confirmLabel: 'Delete',
      variant: 'danger',
      onConfirm: async () => {
        try {
          await sbomsApi.delete(id);
          showNotification('SBOM deleted successfully', 'success');
          refresh();
        } catch {
          showNotification(err instanceof Error ? err.message : 'Failed to delete SBOM', 'error');
        }
      },
    });
  };

  const formatDate = (dateString: string) => {
    const date = new Date(dateString);
    const now = new Date();
    const diffMs = now.getTime() - date.getTime();
    const diffMins = Math.floor(diffMs / 60000);
    const diffHours = Math.floor(diffMs / 3600000);
    const diffDays = Math.floor(diffMs / 86400000);

    if (diffMins < 1) return 'Just now';
    if (diffMins < 60) return `${diffMins}m ago`;
    if (diffHours < 24) return `${diffHours}h ago`;
    if (diffDays < 7) return `${diffDays}d ago`;
    return date.toLocaleDateString();
  };

  const columns = [
    {
      key: 'name',
      header: 'Name',
      render: (item: typeof sboms[0]) => (
        <div>
          <div className="font-medium text-theme-primary">{item.name}</div>
          <div className="text-xs text-theme-tertiary">{item.sbom_id}</div>
        </div>
      ),
    },
    {
      key: 'format',
      header: 'Format',
      render: (item: typeof sboms[0]) => <FormatBadge format={item.format} />,
    },
    {
      key: 'status',
      header: 'Status',
      render: (item: typeof sboms[0]) => <StatusBadge status={item.status} />,
    },
    {
      key: 'component_count',
      header: 'Components',
      render: (item: typeof sboms[0]) => (
        <span className="text-theme-primary">{item.component_count}</span>
      ),
    },
    {
      key: 'vulnerability_count',
      header: 'Vulnerabilities',
      render: (item: typeof sboms[0]) => (
        <span className={item.vulnerability_count > 0 ? 'text-theme-error' : 'text-theme-success'}>
          {item.vulnerability_count}
        </span>
      ),
    },
    {
      key: 'risk_score',
      header: 'Risk Score',
      render: (item: typeof sboms[0]) => <RiskScoreBadge score={item.risk_score} />,
    },
    {
      key: 'ntia_minimum_compliant',
      header: 'NTIA',
      render: (item: typeof sboms[0]) => (
        <div className="flex items-center justify-center">
          {item.ntia_minimum_compliant ? (
            <CheckCircle className="w-4 h-4 text-theme-success" />
          ) : (
            <XCircle className="w-4 h-4 text-theme-error" />
          )}
        </div>
      ),
      width: '80px',
    },
    {
      key: 'created_at',
      header: 'Created',
      render: (item: typeof sboms[0]) => (
        <span className="text-theme-tertiary text-sm">{formatDate(item.created_at)}</span>
      ),
    },
    {
      key: 'actions',
      header: 'Actions',
      render: (item: typeof sboms[0]) => (
        <div className="flex items-center gap-2" onClick={(e) => e.stopPropagation()}>
          <button
            onClick={(e) => {
              e.stopPropagation();
              navigate(`/app/supply-chain/sboms/${item.id}`);
            }}
            className="text-theme-primary hover:text-theme-interactive-primary text-sm"
          >
            View
          </button>
          <button
            onClick={(e) => {
              e.stopPropagation();
              handleDelete(item.id, item.name);
            }}
            className="text-theme-secondary hover:text-theme-error"
          >
            <Trash2 className="w-4 h-4" />
          </button>
        </div>
      ),
      width: '120px',
    },
  ];

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'Supply Chain', href: '/app/supply-chain' },
    { label: 'SBOMs' },
  ];

  // SBOMs are generated via CI/CD pipelines or repository integrations
  const actions = [
    {
      id: 'refresh',
      label: 'Refresh',
      onClick: refresh,
      variant: 'secondary' as const,
      icon: RefreshCw,
    },
  ];

  const tabs = [
    {
      id: 'all',
      label: 'All',
      content: null,
    },
    {
      id: 'completed',
      label: 'Completed',
      content: null,
    },
    {
      id: 'generating',
      label: 'Generating',
      content: null,
    },
    {
      id: 'failed',
      label: 'Failed',
      content: null,
    },
  ];

  const activeTab = statusFilter || 'all';

  const handleTabChange = (tabId: string) => {
    setStatusFilter(tabId === 'all' ? '' : (tabId as SbomStatus));
    setPage(1);
  };

  return (
    <PageContainer
      title="Software Bill of Materials"
      description="Track and manage your software components and dependencies"
      breadcrumbs={breadcrumbs}
      actions={actions}
    >
      <div className="space-y-6">
        <TabContainer
          tabs={tabs}
          activeTab={activeTab}
          onTabChange={handleTabChange}
          variant="underline"
          showContent={false}
        />

        <DataTable
          columns={columns}
          data={sboms}
          loading={loading}
          pagination={pagination || undefined}
          onPageChange={setPage}
          onRowClick={(item) => navigate(`/app/supply-chain/sboms/${item.id}`)}
          emptyState={{
            icon: FileText,
            title: 'No SBOMs Found',
            description: statusFilter
              ? `No ${statusFilter} SBOMs found. Try adjusting your filters.`
              : 'SBOMs are generated via CI/CD pipelines or repository integrations.',
          }}
        />
      </div>
      {ConfirmationDialog}
    </PageContainer>
  );
};

export const SbomsPage: React.FC = () => (
  <PageErrorBoundary>
    <SbomsPageContent />
  </PageErrorBoundary>
);

export default SbomsPage;

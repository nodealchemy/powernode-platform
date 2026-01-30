import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Package } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { TabContainer } from '@/shared/components/ui/TabContainer';
import { DataTable, DataTableColumn } from '@/shared/components/ui/DataTable';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import ErrorAlert from '@/shared/components/ui/ErrorAlert';
import { StatusBadge } from '../components/shared/StatusBadge';
import { useContainerImages } from '../hooks/useContainerImages';
import { useRefreshAction } from '@/shared/hooks/useRefreshAction';
import { ContainerImage } from '../services/containerImagesApi';

type TabId = 'all' | 'verified' | 'unverified' | 'quarantined';

export const ContainerImagesPage: React.FC = () => {
  const navigate = useNavigate();
  const [activeTab, setActiveTab] = useState<TabId>('all');
  const [currentPage, setCurrentPage] = useState(1);

  const statusFilter = activeTab === 'all' ? undefined : activeTab;
  const { images, pagination, loading, error, refresh } = useContainerImages({
    page: currentPage,
    perPage: 20,
    status: statusFilter,
  });

  const handleRowClick = (image: ContainerImage) => {
    navigate(`/app/supply-chain/container-images/${image.id}`);
  };

  const { refreshAction } = useRefreshAction({
    onRefresh: refresh,
    loading,
  });

  const truncateDigest = (digest: string) => {
    if (!digest) return '-';
    const hash = digest.split(':')[1] || digest;
    return `${hash.substring(0, 12)}...`;
  };

  const formatDate = (dateString?: string) => {
    if (!dateString) return 'Never';
    return new Date(dateString).toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    });
  };

  const getVulnCountClasses = (count: number, severity: 'critical' | 'high' | 'medium' | 'low') => {
    if (count === 0) return 'text-theme-muted';

    const severityClasses = {
      critical: 'text-theme-error font-semibold',
      high: 'text-theme-warning font-medium',
      medium: 'text-theme-info',
      low: 'text-theme-success',
    };

    return severityClasses[severity];
  };

  const columns: DataTableColumn<ContainerImage>[] = [
    {
      key: 'image',
      header: 'Image',
      render: (item) => (
        <div className="flex flex-col">
          <span className="font-medium text-theme-primary">
            {item.registry}/{item.repository}
          </span>
          <span className="text-sm text-theme-muted">{item.tag}</span>
        </div>
      ),
    },
    {
      key: 'digest',
      header: 'Digest',
      render: (item) => (
        <code className="text-xs text-theme-muted bg-theme-muted px-2 py-1 rounded">
          {truncateDigest(item.digest)}
        </code>
      ),
    },
    {
      key: 'critical',
      header: 'Critical',
      render: (item) => (
        <span className={getVulnCountClasses(item.critical_vuln_count, 'critical')}>
          {item.critical_vuln_count}
        </span>
      ),
    },
    {
      key: 'high',
      header: 'High',
      render: (item) => (
        <span className={getVulnCountClasses(item.high_vuln_count, 'high')}>
          {item.high_vuln_count}
        </span>
      ),
    },
    {
      key: 'medium',
      header: 'Medium',
      render: (item) => (
        <span className={getVulnCountClasses(item.medium_vuln_count, 'medium')}>
          {item.medium_vuln_count}
        </span>
      ),
    },
    {
      key: 'low',
      header: 'Low',
      render: (item) => (
        <span className={getVulnCountClasses(item.low_vuln_count, 'low')}>
          {item.low_vuln_count}
        </span>
      ),
    },
    {
      key: 'status',
      header: 'Status',
      render: (item) => <StatusBadge status={item.status} size="sm" />,
    },
    {
      key: 'deployed',
      header: 'Deployed',
      render: (item) => (
        <span className={item.is_deployed ? 'text-theme-success' : 'text-theme-muted'}>
          {item.is_deployed ? 'Yes' : 'No'}
        </span>
      ),
    },
    {
      key: 'last_scanned',
      header: 'Last Scanned',
      render: (item) => (
        <span className="text-sm text-theme-secondary">
          {formatDate(item.last_scanned_at)}
        </span>
      ),
    },
  ];

  const tabs = [
    { id: 'all', label: 'All Images' },
    { id: 'verified', label: 'Verified' },
    { id: 'unverified', label: 'Unverified' },
    { id: 'quarantined', label: 'Quarantined' },
  ];

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'Supply Chain', href: '/app/supply-chain' },
    { label: 'Container Images' },
  ];

  const actions = [refreshAction];

  return (
    <PageContainer
      title="Container Images"
      description="Manage and monitor container images with vulnerability scanning and verification"
      breadcrumbs={breadcrumbs}
      actions={actions}
    >
      {error && (
        <div className="mb-6">
          <ErrorAlert message={error} />
        </div>
      )}

      <TabContainer
        tabs={tabs}
        activeTab={activeTab}
        onTabChange={(tabId) => {
          setActiveTab(tabId as TabId);
          setCurrentPage(1);
        }}
        variant="underline"
        showContent={false}
      />

      <div className="mt-6">
        {loading ? (
          <div className="flex justify-center items-center py-12">
            <LoadingSpinner size="lg" />
          </div>
        ) : (
          <DataTable
            columns={columns}
            data={images}
            loading={loading}
            pagination={pagination || undefined}
            onPageChange={setCurrentPage}
            onRowClick={handleRowClick}
            emptyState={{
              icon: Package,
              title: 'No container images found',
              description: activeTab === 'all'
                ? 'Container images are discovered via registry integrations.'
                : `No ${activeTab} container images found.`,
            }}
          />
        )}
      </div>
    </PageContainer>
  );
};

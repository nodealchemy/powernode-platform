import React, { useState } from 'react';
import { useParams } from 'react-router-dom';
import { RefreshCw, ShieldCheck, Ban } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { TabContainer } from '@/shared/components/ui/TabContainer';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import ErrorAlert from '@/shared/components/ui/ErrorAlert';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { StatusBadge } from '../components/shared/StatusBadge';
import { useContainerImage, useContainerVulnerabilities, useContainerSbom, useEvaluatePolicies } from '../hooks/useContainerImages';
import { containerImagesApi } from '../services/containerImagesApi';
import { ContainerVulnerabilitiesTable } from '../components/container/ContainerVulnerabilitiesTable';
import { ContainerSbomViewer } from '../components/container/ContainerSbomViewer';
import { PolicyViolationsList } from '../components/container/PolicyViolationsList';

type TabId = 'overview' | 'vulnerabilities' | 'sbom' | 'policies';

export const ContainerImageDetailPage: React.FC = () => {
  const { id } = useParams<{ id: string }>();
  const [activeTab, setActiveTab] = useState<TabId>('overview');
  const [actionLoading, setActionLoading] = useState(false);

  const { image, loading, error, refresh } = useContainerImage(id || null);
  const { vulnerabilities, loading: vulnLoading } = useContainerVulnerabilities(id || null);
  const { sbom, loading: sbomLoading } = useContainerSbom(id || null);
  const evaluatePolicies = useEvaluatePolicies();
  const [policyResults, setPolicyResults] = useState<Awaited<ReturnType<typeof evaluatePolicies.mutateAsync>> | null>(null);

  const handleEvaluatePolicies = async () => {
    if (!id) return;
    const results = await evaluatePolicies.mutateAsync(id);
    setPolicyResults(results);
  };

  const handleRescan = async () => {
    if (!id) return;
    try {
      setActionLoading(true);
      await containerImagesApi.scan(id);
      refresh();
    } catch {
      // Error handling via global notification
    } finally {
      setActionLoading(false);
    }
  };

  const handleVerify = async () => {
    if (!id) return;
    try {
      setActionLoading(true);
      await containerImagesApi.verify(id);
      refresh();
    } catch {
      // Error handling via global notification
    } finally {
      setActionLoading(false);
    }
  };

  const handleQuarantine = async () => {
    if (!id) return;
    const reason = prompt('Enter reason for quarantine:');
    if (!reason) return;

    try {
      setActionLoading(true);
      await containerImagesApi.quarantine(id, reason);
      refresh();
    } catch {
      // Error handling via global notification
    } finally {
      setActionLoading(false);
    }
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

  if (loading) {
    return (
      <div className="flex justify-center items-center min-h-screen">
        <LoadingSpinner size="lg" />
      </div>
    );
  }

  if (error || !image) {
    return (
      <PageContainer
        title="Container Image"
        breadcrumbs={[
          { label: 'Dashboard', href: '/app' },
          { label: 'Supply Chain', href: '/app/supply-chain' },
          { label: 'Container Images', href: '/app/supply-chain/container-images' },
          { label: 'Details' },
        ]}
      >
        <ErrorAlert message={error || 'Image not found'} />
      </PageContainer>
    );
  }

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'Supply Chain', href: '/app/supply-chain' },
    { label: 'Container Images', href: '/app/supply-chain/container-images' },
    { label: `${image.repository}:${image.tag}` },
  ];

  const actions = [
    {
      id: 'rescan',
      label: 'Re-scan',
      onClick: handleRescan,
      variant: 'outline' as const,
      icon: RefreshCw,
      disabled: actionLoading,
    },
    {
      id: 'verify',
      label: 'Verify',
      onClick: handleVerify,
      variant: 'primary' as const,
      icon: ShieldCheck,
      disabled: actionLoading || image.status === 'verified',
    },
    {
      id: 'quarantine',
      label: 'Quarantine',
      onClick: handleQuarantine,
      variant: 'danger' as const,
      icon: Ban,
      disabled: actionLoading || image.status === 'quarantined',
    },
  ];

  const tabs = [
    { id: 'overview', label: 'Overview' },
    { id: 'vulnerabilities', label: 'Vulnerabilities' },
    { id: 'sbom', label: 'SBOM' },
    { id: 'policies', label: 'Policies' },
  ];

  const renderOverview = () => (
    <div className="space-y-6">
      <Card className="p-6">
        <h2 className="text-lg font-semibold text-theme-primary mb-4">Image Details</h2>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div>
            <span className="text-sm font-medium text-theme-muted">Registry</span>
            <p className="text-theme-primary mt-1">{image.registry}</p>
          </div>
          <div>
            <span className="text-sm font-medium text-theme-muted">Repository</span>
            <p className="text-theme-primary mt-1">{image.repository}</p>
          </div>
          <div>
            <span className="text-sm font-medium text-theme-muted">Tag</span>
            <p className="text-theme-primary mt-1">{image.tag}</p>
          </div>
          <div>
            <span className="text-sm font-medium text-theme-muted">Digest</span>
            <code className="text-xs text-theme-muted bg-theme-muted px-2 py-1 rounded block mt-1">
              {image.digest}
            </code>
          </div>
          <div>
            <span className="text-sm font-medium text-theme-muted">Status</span>
            <div className="mt-1">
              <StatusBadge status={image.status} />
            </div>
          </div>
          <div>
            <span className="text-sm font-medium text-theme-muted">Deployed</span>
            <div className="mt-1">
              <Badge variant={image.is_deployed ? 'success' : 'secondary'}>
                {image.is_deployed ? 'Yes' : 'No'}
              </Badge>
            </div>
          </div>
          <div>
            <span className="text-sm font-medium text-theme-muted">Last Scanned</span>
            <p className="text-theme-primary mt-1">{formatDate(image.last_scanned_at)}</p>
          </div>
          <div>
            <span className="text-sm font-medium text-theme-muted">Created</span>
            <p className="text-theme-primary mt-1">{formatDate(image.created_at)}</p>
          </div>
        </div>
      </Card>

      <Card className="p-6">
        <h2 className="text-lg font-semibold text-theme-primary mb-4">Vulnerability Summary</h2>
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <div className="text-center p-4 bg-theme-error/10 rounded-lg">
            <div className="text-3xl font-bold text-theme-error">
              {image.critical_vuln_count}
            </div>
            <div className="text-sm text-theme-muted mt-1">Critical</div>
          </div>
          <div className="text-center p-4 bg-theme-warning/10 rounded-lg">
            <div className="text-3xl font-bold text-theme-warning">
              {image.high_vuln_count}
            </div>
            <div className="text-sm text-theme-muted mt-1">High</div>
          </div>
          <div className="text-center p-4 bg-theme-info/10 rounded-lg">
            <div className="text-3xl font-bold text-theme-info">
              {image.medium_vuln_count}
            </div>
            <div className="text-sm text-theme-muted mt-1">Medium</div>
          </div>
          <div className="text-center p-4 bg-theme-success/10 rounded-lg">
            <div className="text-3xl font-bold text-theme-success">
              {image.low_vuln_count}
            </div>
            <div className="text-sm text-theme-muted mt-1">Low</div>
          </div>
        </div>
      </Card>

      {image.scans && image.scans.length > 0 && (
        <Card className="p-6">
          <h2 className="text-lg font-semibold text-theme-primary mb-4">Scan History</h2>
          <div className="space-y-3">
            {image.scans.map((scan) => (
              <div
                key={scan.id}
                className="flex items-center justify-between p-3 bg-theme-muted rounded-lg"
              >
                <div className="flex-1">
                  <div className="flex items-center gap-3">
                    <span className="font-medium text-theme-primary">{scan.scanner}</span>
                    <StatusBadge status={scan.status as 'pending' | 'running' | 'completed' | 'failed'} size="sm" />
                  </div>
                  <div className="text-sm text-theme-muted mt-1">
                    {formatDate(scan.started_at)} - {formatDate(scan.completed_at)}
                  </div>
                </div>
                <div className="flex gap-4 text-sm">
                  <span className="text-theme-error">C: {scan.critical_count}</span>
                  <span className="text-theme-warning">H: {scan.high_count}</span>
                  <span className="text-theme-info">M: {scan.medium_count}</span>
                  <span className="text-theme-success">L: {scan.low_count}</span>
                </div>
              </div>
            ))}
          </div>
        </Card>
      )}
    </div>
  );

  const renderVulnerabilities = () => (
    <ContainerVulnerabilitiesTable
      vulnerabilities={vulnerabilities || []}
      loading={vulnLoading}
    />
  );

  const renderSBOM = () => (
    <ContainerSbomViewer
      sbom={sbom || null}
      loading={sbomLoading}
    />
  );

  const renderPolicies = () => (
    <PolicyViolationsList
      evaluations={policyResults}
      loading={evaluatePolicies.isLoading}
      onEvaluate={handleEvaluatePolicies}
    />
  );

  return (
    <PageContainer
      title={`${image.repository}:${image.tag}`}
      description={`Registry: ${image.registry}`}
      breadcrumbs={breadcrumbs}
      actions={actions}
    >
      <div className="mb-6 flex items-center gap-3">
        <StatusBadge status={image.status} />
        {image.is_deployed && (
          <Badge variant="success">Deployed</Badge>
        )}
      </div>

      <TabContainer
        tabs={tabs}
        activeTab={activeTab}
        onTabChange={(tabId) => setActiveTab(tabId as TabId)}
        variant="underline"
        showContent={false}
      />

      <div className="mt-6">
        {activeTab === 'overview' && renderOverview()}
        {activeTab === 'vulnerabilities' && renderVulnerabilities()}
        {activeTab === 'sbom' && renderSBOM()}
        {activeTab === 'policies' && renderPolicies()}
      </div>
    </PageContainer>
  );
};

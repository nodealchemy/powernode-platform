import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { FileSignature, Check, X } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { TabContainer } from '@/shared/components/ui/TabContainer';
import { DataTable, DataTableColumn } from '@/shared/components/ui/DataTable';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import ErrorAlert from '@/shared/components/ui/ErrorAlert';
import { Badge } from '@/shared/components/ui/Badge';
import { StatusBadge } from '../components/shared/StatusBadge';
import { useAttestations } from '../hooks/useAttestations';
import { Attestation, AttestationType } from '../services/attestationsApi';

type TabId = 'all' | 'slsa_provenance' | 'sbom' | 'custom';

export const AttestationsPage: React.FC = () => {
  const navigate = useNavigate();
  const [activeTab, setActiveTab] = useState<TabId>('all');
  const [currentPage, setCurrentPage] = useState(1);

  const typeFilter = activeTab === 'all' ? undefined : (activeTab as AttestationType);
  const { attestations, pagination, loading, error } = useAttestations({
    page: currentPage,
    perPage: 20,
    attestationType: typeFilter,
  });

  const handleCreateAttestation = () => {
    navigate('/app/supply-chain/attestations/create');
  };

  const handleRowClick = (attestation: Attestation) => {
    navigate(`/app/supply-chain/attestations/${attestation.id}`);
  };

  const formatDate = (dateString: string) => {
    return new Date(dateString).toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    });
  };

  const getTypeLabel = (type: AttestationType) => {
    const labels: Record<AttestationType, string> = {
      slsa_provenance: 'SLSA Provenance',
      sbom: 'SBOM',
      vulnerability_scan: 'Vulnerability Scan',
      custom: 'Custom',
    };
    return labels[type] || type;
  };

  const truncateDigest = (digest: string) => {
    if (!digest) return '-';
    const hash = digest.split(':')[1] || digest;
    return `${hash.substring(0, 12)}...`;
  };

  const columns: DataTableColumn<Attestation>[] = [
    {
      key: 'subject',
      header: 'Subject',
      render: (item) => (
        <div className="flex flex-col">
          <span className="font-medium text-theme-primary">{item.subject_name}</span>
          <code className="text-xs text-theme-muted">
            {truncateDigest(item.subject_digest)}
          </code>
        </div>
      ),
    },
    {
      key: 'type',
      header: 'Type',
      render: (item) => (
        <Badge variant="info" size="sm">
          {getTypeLabel(item.attestation_type)}
        </Badge>
      ),
    },
    {
      key: 'slsa_level',
      header: 'SLSA Level',
      render: (item) => {
        if (!item.slsa_level) return <span className="text-theme-muted">-</span>;
        const levelColors = {
          1: 'secondary' as const,
          2: 'warning' as const,
          3: 'success' as const,
        };
        return (
          <Badge variant={levelColors[item.slsa_level]} size="sm">
            Level {item.slsa_level}
          </Badge>
        );
      },
    },
    {
      key: 'signed',
      header: 'Signed',
      render: (item) => (
        <div className="flex items-center justify-center">
          {item.signed ? (
            <Check className="w-5 h-5 text-theme-success" />
          ) : (
            <X className="w-5 h-5 text-theme-muted" />
          )}
        </div>
      ),
    },
    {
      key: 'verified',
      header: 'Verified',
      render: (item) => (
        <StatusBadge status={item.verification_status} size="sm" />
      ),
    },
    {
      key: 'rekor',
      header: 'Rekor',
      render: (item) => (
        <div className="flex items-center justify-center">
          {item.rekor_logged ? (
            <Check className="w-5 h-5 text-theme-success" />
          ) : (
            <X className="w-5 h-5 text-theme-muted" />
          )}
        </div>
      ),
    },
    {
      key: 'created',
      header: 'Created',
      render: (item) => (
        <span className="text-sm text-theme-secondary">
          {formatDate(item.created_at)}
        </span>
      ),
    },
  ];

  const tabs = [
    { id: 'all', label: 'All Attestations' },
    { id: 'slsa_provenance', label: 'SLSA Provenance' },
    { id: 'sbom', label: 'SBOM' },
    { id: 'custom', label: 'Custom' },
  ];

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'Supply Chain', href: '/app/supply-chain' },
    { label: 'Attestations' },
  ];

  const actions = [
    {
      id: 'create-attestation',
      label: 'Create Attestation',
      onClick: handleCreateAttestation,
      variant: 'primary' as const,
      icon: FileSignature,
    },
  ];

  return (
    <PageContainer
      title="Attestations"
      description="Manage cryptographic attestations for supply chain artifacts"
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
            data={attestations}
            loading={loading}
            pagination={pagination || undefined}
            onPageChange={setCurrentPage}
            onRowClick={handleRowClick}
            emptyState={{
              icon: FileSignature,
              title: 'No attestations found',
              description: activeTab === 'all'
                ? 'Get started by creating your first attestation.'
                : `No ${getTypeLabel(activeTab as AttestationType)} attestations found.`,
              action: {
                label: 'Create Attestation',
                onClick: handleCreateAttestation,
              },
            }}
          />
        )}
      </div>
    </PageContainer>
  );
};

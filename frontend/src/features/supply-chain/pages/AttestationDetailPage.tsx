import React, { useState } from 'react';
import { useParams } from 'react-router-dom';
import { ShieldCheck, Download, BookOpen, History, Key } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { TabContainer } from '@/shared/components/ui/TabContainer';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import ErrorAlert from '@/shared/components/ui/ErrorAlert';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { StatusBadge } from '../components/shared/StatusBadge';
import { useAttestation, useSignAttestation } from '../hooks/useAttestations';
import { attestationsApi, AttestationType } from '../services/attestationsApi';
import { SignAttestationModal } from '../components/attestation/SignAttestationModal';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { formatDateTime } from '@/shared/utils/formatters';

type TabId = 'overview' | 'provenance' | 'verification';

export const AttestationDetailPage: React.FC = () => {
  const { id } = useParams<{ id: string }>();
  const [activeTab, setActiveTab] = useState<TabId>('overview');
  const [actionLoading, setActionLoading] = useState(false);

  const { attestation, loading, error, refresh } = useAttestation(id || null);
  const signMutation = useSignAttestation();
  const { showNotification } = useNotifications();
  const [showSignModal, setShowSignModal] = useState(false);

  const handleSign = async (signingKeyId?: string) => {
    if (!id) return;
    try {
      await signMutation.mutateAsync({ id, signingKeyId });
      showNotification('Attestation signed successfully', 'success');
      setShowSignModal(false);
      refresh();
    } catch (_error) {
      showNotification('Failed to sign attestation', 'error');
    }
  };

  const handleVerify = async () => {
    if (!id) return;
    try {
      setActionLoading(true);
      await attestationsApi.verify(id);
      refresh();
    } catch (_error) {
      // Error handling via global notification
    } finally {
      setActionLoading(false);
    }
  };

  const handleRecordToRekor = async () => {
    if (!id) return;
    try {
      setActionLoading(true);
      await attestationsApi.recordToRekor(id);
      refresh();
    } catch (_error) {
      // Error handling via global notification
    } finally {
      setActionLoading(false);
    }
  };

  const handleDownload = () => {
    if (!attestation) return;
    const dataStr = JSON.stringify(attestation, null, 2);
    const dataUri = 'data:application/json;charset=utf-8,' + encodeURIComponent(dataStr);
    const exportFileDefaultName = `attestation-${attestation.attestation_id}.json`;

    const linkElement = document.createElement('a');
    linkElement.setAttribute('href', dataUri);
    linkElement.setAttribute('download', exportFileDefaultName);
    linkElement.click();
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


  if (loading) {
    return (
      <div className="flex justify-center items-center min-h-screen">
        <LoadingSpinner size="lg" />
      </div>
    );
  }

  if (error || !attestation) {
    return (
      <PageContainer
        title="Attestation"
        breadcrumbs={[
          { label: 'Dashboard', href: '/app' },
          { label: 'Supply Chain', href: '/app/supply-chain' },
          { label: 'Attestations', href: '/app/supply-chain/attestations' },
          { label: 'Details' },
        ]}
      >
        <ErrorAlert message={error || 'Attestation not found'} />
      </PageContainer>
    );
  }

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'Supply Chain', href: '/app/supply-chain' },
    { label: 'Attestations', href: '/app/supply-chain/attestations' },
    { label: attestation.subject_name },
  ];

  const actions = [
    {
      id: 'sign',
      label: 'Sign',
      onClick: () => setShowSignModal(true),
      variant: 'primary' as const,
      icon: Key,
      disabled: actionLoading || attestation.signed,
    },
    {
      id: 'verify',
      label: 'Verify',
      onClick: handleVerify,
      variant: 'secondary' as const,
      icon: ShieldCheck,
      disabled: actionLoading,
    },
    {
      id: 'record-rekor',
      label: 'Record to Rekor',
      onClick: handleRecordToRekor,
      variant: 'outline' as const,
      icon: BookOpen,
      disabled: actionLoading || attestation.rekor_logged,
    },
    {
      id: 'download',
      label: 'Download',
      onClick: handleDownload,
      variant: 'outline' as const,
      icon: Download,
    },
  ];

  const tabs = [
    { id: 'overview', label: 'Overview' },
    { id: 'provenance', label: 'Provenance' },
    { id: 'verification', label: 'Verification History' },
  ];

  const renderOverview = () => (
    <div className="space-y-6">
      <Card className="p-6">
        <h2 className="text-lg font-semibold text-theme-primary mb-4">Attestation Details</h2>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div>
            <span className="text-sm font-medium text-theme-muted">Attestation ID</span>
            <code className="text-xs text-theme-muted bg-theme-muted px-2 py-1 rounded block mt-1">
              {attestation.attestation_id}
            </code>
          </div>
          <div>
            <span className="text-sm font-medium text-theme-muted">Type</span>
            <div className="mt-1">
              <Badge variant="info">{getTypeLabel(attestation.attestation_type)}</Badge>
            </div>
          </div>
          <div>
            <span className="text-sm font-medium text-theme-muted">Subject Name</span>
            <p className="text-theme-primary mt-1">{attestation.subject_name}</p>
          </div>
          <div>
            <span className="text-sm font-medium text-theme-muted">Subject Digest</span>
            <code className="text-xs text-theme-muted bg-theme-muted px-2 py-1 rounded block mt-1">
              {attestation.subject_digest}
            </code>
          </div>
          {attestation.slsa_level && (
            <div>
              <span className="text-sm font-medium text-theme-muted">SLSA Level</span>
              <div className="mt-1">
                <Badge
                  variant={
                    attestation.slsa_level === 3 ? 'success' :
                    attestation.slsa_level === 2 ? 'warning' :
                    'secondary'
                  }
                >
                  Level {attestation.slsa_level}
                </Badge>
              </div>
            </div>
          )}
          <div>
            <span className="text-sm font-medium text-theme-muted">Verification Status</span>
            <div className="mt-1">
              <StatusBadge status={attestation.verification_status} />
            </div>
          </div>
          <div>
            <span className="text-sm font-medium text-theme-muted">Signed</span>
            <div className="mt-1">
              <Badge variant={attestation.signed ? 'success' : 'secondary'}>
                {attestation.signed ? 'Yes' : 'No'}
              </Badge>
            </div>
          </div>
          <div>
            <span className="text-sm font-medium text-theme-muted">Rekor Logged</span>
            <div className="mt-1">
              <Badge variant={attestation.rekor_logged ? 'success' : 'secondary'}>
                {attestation.rekor_logged ? 'Yes' : 'No'}
              </Badge>
            </div>
          </div>
          <div>
            <span className="text-sm font-medium text-theme-muted">Created</span>
            <p className="text-theme-primary mt-1">{formatDateTime(attestation.created_at)}</p>
          </div>
          <div>
            <span className="text-sm font-medium text-theme-muted">Updated</span>
            <p className="text-theme-primary mt-1">{formatDateTime(attestation.updated_at)}</p>
          </div>
        </div>
      </Card>

      {attestation.signing_key && (
        <Card className="p-6">
          <h2 className="text-lg font-semibold text-theme-primary mb-4">Signing Key</h2>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <span className="text-sm font-medium text-theme-muted">Name</span>
              <p className="text-theme-primary mt-1">{attestation.signing_key.name}</p>
            </div>
            <div>
              <span className="text-sm font-medium text-theme-muted">Key Type</span>
              <p className="text-theme-primary mt-1">{attestation.signing_key.key_type}</p>
            </div>
            <div>
              <span className="text-sm font-medium text-theme-muted">Default Key</span>
              <div className="mt-1">
                <Badge variant={attestation.signing_key.is_default ? 'success' : 'secondary'}>
                  {attestation.signing_key.is_default ? 'Yes' : 'No'}
                </Badge>
              </div>
            </div>
          </div>
        </Card>
      )}
    </div>
  );

  const renderProvenance = () => {
    if (!attestation.build_provenance) {
      return (
        <Card className="p-6">
          <div className="text-center py-12 text-theme-muted">
            <BookOpen className="w-12 h-12 mx-auto mb-4 opacity-50" />
            <p>No build provenance data available</p>
          </div>
        </Card>
      );
    }

    const { build_provenance } = attestation;

    return (
      <div className="space-y-6">
        <Card className="p-6">
          <h2 className="text-lg font-semibold text-theme-primary mb-4">Builder Information</h2>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <span className="text-sm font-medium text-theme-muted">Builder ID</span>
              <code className="text-xs text-theme-muted bg-theme-muted px-2 py-1 rounded block mt-1">
                {build_provenance.builder_id}
              </code>
            </div>
            <div>
              <span className="text-sm font-medium text-theme-muted">Build Type</span>
              <p className="text-theme-primary mt-1">{build_provenance.build_type}</p>
            </div>
          </div>
        </Card>

        {build_provenance.materials && build_provenance.materials.length > 0 && (
          <Card className="p-6">
            <h2 className="text-lg font-semibold text-theme-primary mb-4">Materials</h2>
            <div className="space-y-3">
              {build_provenance.materials.map((material, index) => (
                <div key={index} className="p-3 bg-theme-muted rounded-lg">
                  <div className="text-sm font-medium text-theme-primary mb-2">
                    {material.uri}
                  </div>
                  <div className="space-y-1">
                    {Object.entries(material.digest).map(([algo, hash]) => (
                      <div key={algo} className="flex items-center gap-2">
                        <span className="text-xs text-theme-muted uppercase">{algo}:</span>
                        <code className="text-xs text-theme-muted">{hash}</code>
                      </div>
                    ))}
                  </div>
                </div>
              ))}
            </div>
          </Card>
        )}

        <Card className="p-6">
          <h2 className="text-lg font-semibold text-theme-primary mb-4">Invocation Details</h2>
          <pre className="text-xs text-theme-muted bg-theme-muted p-4 rounded-lg overflow-x-auto">
            {JSON.stringify(build_provenance.invocation, null, 2)}
          </pre>
        </Card>
      </div>
    );
  };

  const renderVerification = () => {
    if (!attestation.verification_logs || attestation.verification_logs.length === 0) {
      return (
        <Card className="p-6">
          <div className="text-center py-12 text-theme-muted">
            <History className="w-12 h-12 mx-auto mb-4 opacity-50" />
            <p>No verification history available</p>
          </div>
        </Card>
      );
    }

    return (
      <Card className="p-6">
        <h2 className="text-lg font-semibold text-theme-primary mb-4">Verification Log</h2>
        <div className="space-y-3">
          {attestation.verification_logs.map((log, index) => (
            <div key={index} className="p-4 bg-theme-muted rounded-lg">
              <div className="flex items-start justify-between mb-2">
                <StatusBadge status={log.status} />
                <span className="text-sm text-theme-muted">
                  {formatDateTime(log.verified_at)}
                </span>
              </div>
              {log.message && (
                <p className="text-sm text-theme-secondary mt-2">{log.message}</p>
              )}
            </div>
          ))}
        </div>
      </Card>
    );
  };

  return (
    <PageContainer
      title={attestation.subject_name}
      description={`Attestation ID: ${attestation.attestation_id}`}
      breadcrumbs={breadcrumbs}
      actions={actions}
    >
      <div className="mb-6 flex items-center gap-3">
        <Badge variant="info">{getTypeLabel(attestation.attestation_type)}</Badge>
        {attestation.slsa_level && (
          <Badge
            variant={
              attestation.slsa_level === 3 ? 'success' :
              attestation.slsa_level === 2 ? 'warning' :
              'secondary'
            }
          >
            SLSA Level {attestation.slsa_level}
          </Badge>
        )}
        <StatusBadge status={attestation.verification_status} />
        {attestation.signed && <Badge variant="success">Signed</Badge>}
        {attestation.rekor_logged && <Badge variant="success">Rekor Logged</Badge>}
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
        {activeTab === 'provenance' && renderProvenance()}
        {activeTab === 'verification' && renderVerification()}
      </div>

      {showSignModal && (
        <SignAttestationModal
          attestationId={attestation.id}
          onClose={() => setShowSignModal(false)}
          onSign={handleSign}
          attestationName={attestation.subject_name}
        />
      )}
    </PageContainer>
  );
};

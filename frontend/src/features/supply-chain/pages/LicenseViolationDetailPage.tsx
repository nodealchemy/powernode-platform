import React, { useState } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { ArrowLeft, AlertTriangle, FileText, History, CheckCircle, XCircle } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import ErrorAlert from '@/shared/components/ui/ErrorAlert';
import { SeverityBadge } from '../components/shared/SeverityBadge';
import {
  useLicenseViolation,
  useResolveViolation,
  useGrantViolationException,
  useRequestException,
} from '../hooks/useLicenseCompliance';
import { useNotifications } from '@/shared/hooks/useNotifications';

export const LicenseViolationDetailPage: React.FC = () => {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { showNotification } = useNotifications();

  const { data: violation, isLoading, error, refetch } = useLicenseViolation(id || '');
  const resolveMutation = useResolveViolation();
  const grantExceptionMutation = useGrantViolationException();
  const requestExceptionMutation = useRequestException();

  const [showRequestModal, setShowRequestModal] = useState(false);
  const [justification, setJustification] = useState('');

  const handleResolve = async () => {
    if (!id) return;
    const note = window.prompt('Enter resolution note (optional):');
    if (note !== null) {
      try {
        await resolveMutation.mutateAsync({ id, note: note || undefined });
        showNotification('Violation resolved successfully', 'success');
        refetch();
      } catch (_error) {
        showNotification('Failed to resolve violation', 'error');
      }
    }
  };

  const handleGrantException = async () => {
    if (!id) return;
    const note = window.prompt('Enter exception justification (required):');
    if (note && note.trim()) {
      try {
        await grantExceptionMutation.mutateAsync({ id, note });
        showNotification('Exception granted successfully', 'success');
        refetch();
      } catch (_error) {
        showNotification('Failed to grant exception', 'error');
      }
    }
  };

  const handleRequestException = async () => {
    if (!id || !justification.trim()) return;
    try {
      await requestExceptionMutation.mutateAsync({ id, justification });
      showNotification('Exception request submitted', 'success');
      setShowRequestModal(false);
      setJustification('');
      refetch();
    } catch (_error) {
      showNotification('Failed to request exception', 'error');
    }
  };

  if (isLoading) {
    return (
      <div className="flex justify-center items-center min-h-screen">
        <LoadingSpinner size="lg" />
      </div>
    );
  }

  if (error || !violation) {
    return (
      <PageContainer
        title="License Violation"
        breadcrumbs={[
          { label: 'Dashboard', href: '/app' },
          { label: 'Supply Chain', href: '/app/supply-chain' },
          { label: 'License Violations', href: '/app/supply-chain/licenses/violations' },
          { label: 'Details' },
        ]}
      >
        <ErrorAlert message={error || 'Violation not found'} />
      </PageContainer>
    );
  }

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'Supply Chain', href: '/app/supply-chain' },
    { label: 'License Violations', href: '/app/supply-chain/licenses/violations' },
    { label: `${violation.component_name}@${violation.component_version}` },
  ];

  const actions = [
    {
      id: 'back',
      label: 'Back to Violations',
      onClick: () => navigate('/app/supply-chain/licenses/violations'),
      variant: 'secondary' as const,
      icon: ArrowLeft,
    },
  ];

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'resolved':
        return <CheckCircle className="w-5 h-5 text-theme-success" />;
      case 'exception_granted':
        return <CheckCircle className="w-5 h-5 text-theme-info" />;
      default:
        return <XCircle className="w-5 h-5 text-theme-error" />;
    }
  };

  const getStatusBadgeVariant = (status: string) => {
    switch (status) {
      case 'resolved':
        return 'success';
      case 'exception_granted':
        return 'info';
      default:
        return 'warning';
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
      denied: 'Denied License',
      copyleft_contamination: 'Copyleft Contamination',
      incompatible: 'Incompatible License',
      unknown_license: 'Unknown License',
    };
    return <Badge variant={variants[type] || 'secondary'}>{labels[type] || type}</Badge>;
  };

  return (
    <PageContainer
      title={`${violation.component_name}@${violation.component_version}`}
      description="License compliance violation details"
      breadcrumbs={breadcrumbs}
      actions={actions}
    >
      <div className="mb-6 flex items-center gap-3">
        {getStatusIcon(violation.status)}
        <Badge variant={getStatusBadgeVariant(violation.status)}>
          {violation.status === 'exception_granted' ? 'Exception Granted' : violation.status}
        </Badge>
        <SeverityBadge severity={violation.severity} />
      </div>

      <div className="space-y-6">
        <Card className="p-6">
          <h3 className="text-lg font-semibold text-theme-primary mb-4">Violation Details</h3>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <span className="text-sm text-theme-secondary">Component</span>
              <p className="text-theme-primary font-medium">{violation.component_name}</p>
            </div>
            <div>
              <span className="text-sm text-theme-secondary">Version</span>
              <p className="text-theme-primary font-medium">{violation.component_version}</p>
            </div>
            <div>
              <span className="text-sm text-theme-secondary">License</span>
              <p className="text-theme-primary font-medium">
                {violation.license_name}
                {violation.license_spdx_id && (
                  <span className="text-theme-secondary ml-1">({violation.license_spdx_id})</span>
                )}
              </p>
            </div>
            <div>
              <span className="text-sm text-theme-secondary">Violation Type</span>
              <div className="mt-1">{getViolationTypeBadge(violation.violation_type)}</div>
            </div>
            <div>
              <span className="text-sm text-theme-secondary">Detected</span>
              <p className="text-theme-primary">
                {new Date(violation.created_at).toLocaleDateString()}
              </p>
            </div>
            {violation.resolved_at && (
              <div>
                <span className="text-sm text-theme-secondary">Resolved</span>
                <p className="text-theme-primary">
                  {new Date(violation.resolved_at).toLocaleDateString()}
                </p>
              </div>
            )}
          </div>

          {violation.resolution_note && (
            <div className="mt-4 p-4 bg-theme-success/10 rounded-lg">
              <div className="flex items-center gap-2 mb-2">
                <FileText className="w-4 h-4 text-theme-success" />
                <span className="font-medium text-theme-success">Resolution Note</span>
              </div>
              <p className="text-sm text-theme-primary">{violation.resolution_note}</p>
            </div>
          )}
        </Card>

        {violation.status === 'open' && (
          <Card className="p-6">
            <h3 className="text-lg font-semibold text-theme-primary mb-4">Actions</h3>
            <div className="flex flex-wrap gap-3">
              <Button
                variant="success"
                onClick={handleResolve}
                disabled={resolveMutation.isLoading}
              >
                {resolveMutation.isLoading ? 'Resolving...' : 'Mark as Resolved'}
              </Button>
              <Button
                variant="secondary"
                onClick={handleGrantException}
                disabled={grantExceptionMutation.isLoading}
              >
                {grantExceptionMutation.isLoading ? 'Granting...' : 'Grant Exception'}
              </Button>
              <Button
                variant="outline"
                onClick={() => setShowRequestModal(true)}
              >
                Request Exception
              </Button>
            </div>
          </Card>
        )}

        <Card className="p-6">
          <h3 className="text-lg font-semibold text-theme-primary mb-4 flex items-center gap-2">
            <History className="w-5 h-5" />
            Activity History
          </h3>
          <div className="space-y-4">
            <div className="flex items-start gap-3 p-3 bg-theme-muted rounded-lg">
              <AlertTriangle className="w-5 h-5 text-theme-warning flex-shrink-0 mt-0.5" />
              <div>
                <p className="font-medium text-theme-primary">Violation Detected</p>
                <p className="text-sm text-theme-secondary">
                  {new Date(violation.created_at).toLocaleString()}
                </p>
              </div>
            </div>
            {violation.resolved_at && (
              <div className="flex items-start gap-3 p-3 bg-theme-muted rounded-lg">
                <CheckCircle className="w-5 h-5 text-theme-success flex-shrink-0 mt-0.5" />
                <div>
                  <p className="font-medium text-theme-primary">
                    {violation.status === 'exception_granted' ? 'Exception Granted' : 'Resolved'}
                  </p>
                  <p className="text-sm text-theme-secondary">
                    {new Date(violation.resolved_at).toLocaleString()}
                  </p>
                </div>
              </div>
            )}
          </div>
        </Card>
      </div>

      {showRequestModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center">
          <div className="fixed inset-0 bg-black/50" onClick={() => setShowRequestModal(false)} />
          <div className="relative z-10 w-full max-w-md bg-theme-surface rounded-lg shadow-xl mx-4 p-6">
            <h3 className="text-lg font-semibold text-theme-primary mb-4">Request Exception</h3>
            <div className="mb-4">
              <label className="block text-sm font-medium text-theme-secondary mb-2">
                Justification *
              </label>
              <textarea
                value={justification}
                onChange={(e) => setJustification(e.target.value)}
                placeholder="Explain why an exception should be granted..."
                rows={4}
                className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
              />
            </div>
            <div className="flex justify-end gap-3">
              <Button variant="secondary" onClick={() => setShowRequestModal(false)}>
                Cancel
              </Button>
              <Button
                variant="primary"
                onClick={handleRequestException}
                disabled={!justification.trim() || requestExceptionMutation.isLoading}
              >
                {requestExceptionMutation.isLoading ? 'Submitting...' : 'Submit Request'}
              </Button>
            </div>
          </div>
        </div>
      )}
    </PageContainer>
  );
};

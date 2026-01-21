import React, { useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { Edit, Trash2, Power, PowerOff, Shield, AlertTriangle, CheckCircle, XCircle } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import ErrorAlert from '@/shared/components/ui/ErrorAlert';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { useNotifications } from '@/shared/hooks/useNotifications';
import {
  useLicensePolicy,
  useDeleteLicensePolicy,
  useToggleLicensePolicyActive,
} from '../hooks/useLicenseCompliance';

const POLICY_TYPE_LABELS: Record<string, string> = {
  allowlist: 'Allowlist',
  denylist: 'Denylist',
  hybrid: 'Hybrid',
};

const ENFORCEMENT_LABELS: Record<string, { label: string; variant: 'info' | 'warning' | 'danger' }> = {
  log: { label: 'Log Only', variant: 'info' },
  warn: { label: 'Warn', variant: 'warning' },
  block: { label: 'Block', variant: 'danger' },
};

export const LicensePolicyDetailPage: React.FC = () => {
  const navigate = useNavigate();
  const { id } = useParams<{ id: string }>();
  const { showNotification } = useNotifications();
  const { confirm, ConfirmationDialog } = useConfirmation();
  const [actionLoading, setActionLoading] = useState(false);

  const { data: policy, isLoading, error, refetch } = useLicensePolicy(id || '');
  const deleteMutation = useDeleteLicensePolicy();
  const toggleActiveMutation = useToggleLicensePolicyActive();

  const handleEdit = () => {
    navigate(`/app/supply-chain/licenses/policies/${id}/edit`);
  };

  const handleDelete = () => {
    confirm({
      title: 'Delete License Policy',
      message: `Are you sure you want to delete "${policy?.name}"? This action cannot be undone.`,
      confirmLabel: 'Delete',
      variant: 'danger',
      onConfirm: async () => {
        try {
          await deleteMutation.mutateAsync(id!);
          showNotification('License policy deleted successfully', 'success');
          navigate('/app/supply-chain/licenses/policies');
        } catch (err) {
          showNotification(
            err instanceof Error ? err.message : 'Failed to delete policy',
            'error'
          );
        }
      },
    });
  };

  const handleToggleActive = async () => {
    if (!policy) return;

    try {
      setActionLoading(true);
      await toggleActiveMutation.mutateAsync({ id: id!, isActive: !policy.is_active });
      showNotification(
        `Policy ${policy.is_active ? 'deactivated' : 'activated'} successfully`,
        'success'
      );
      refetch();
    } catch (err) {
      showNotification(
        err instanceof Error ? err.message : 'Failed to update policy',
        'error'
      );
    } finally {
      setActionLoading(false);
    }
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

  if (isLoading) {
    return (
      <div className="flex justify-center items-center min-h-screen">
        <LoadingSpinner size="lg" />
      </div>
    );
  }

  if (error || !policy) {
    return (
      <PageContainer
        title="License Policy"
        breadcrumbs={[
          { label: 'Dashboard', href: '/app' },
          { label: 'Supply Chain', href: '/app/supply-chain' },
          { label: 'License Policies', href: '/app/supply-chain/licenses/policies' },
          { label: 'Details' },
        ]}
      >
        <ErrorAlert message="Failed to load license policy" />
      </PageContainer>
    );
  }

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'Supply Chain', href: '/app/supply-chain' },
    { label: 'License Policies', href: '/app/supply-chain/licenses/policies' },
    { label: policy.name },
  ];

  const actions = [
    {
      id: 'toggle-active',
      label: policy.is_active ? 'Deactivate' : 'Activate',
      onClick: handleToggleActive,
      variant: 'outline' as const,
      icon: policy.is_active ? PowerOff : Power,
      disabled: actionLoading,
    },
    {
      id: 'edit',
      label: 'Edit',
      onClick: handleEdit,
      variant: 'outline' as const,
      icon: Edit,
    },
    {
      id: 'delete',
      label: 'Delete',
      onClick: handleDelete,
      variant: 'danger' as const,
      icon: Trash2,
    },
  ];

  const enforcementConfig = ENFORCEMENT_LABELS[policy.enforcement_level] || ENFORCEMENT_LABELS.log;

  return (
    <PageContainer
      title={policy.name}
      description={policy.description || 'License compliance policy'}
      breadcrumbs={breadcrumbs}
      actions={actions}
    >
      <div className="space-y-6">
        {/* Status Badges */}
        <div className="flex items-center gap-3">
          <Badge variant={policy.is_active ? 'success' : 'secondary'}>
            {policy.is_active ? 'Active' : 'Inactive'}
          </Badge>
          <Badge variant="info">{POLICY_TYPE_LABELS[policy.policy_type]}</Badge>
          <Badge variant={enforcementConfig.variant}>{enforcementConfig.label}</Badge>
          {policy.is_default && <Badge variant="primary">Default</Badge>}
        </div>

        {/* Policy Details */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <Card className="p-6">
            <h2 className="text-lg font-semibold text-theme-primary mb-4">Policy Configuration</h2>
            <div className="space-y-4">
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <span className="text-sm font-medium text-theme-muted">Policy Type</span>
                  <p className="text-theme-primary mt-1">{POLICY_TYPE_LABELS[policy.policy_type]}</p>
                </div>
                <div>
                  <span className="text-sm font-medium text-theme-muted">Enforcement Level</span>
                  <p className={`mt-1 ${
                    policy.enforcement_level === 'block' ? 'text-theme-error' :
                    policy.enforcement_level === 'warn' ? 'text-theme-warning' :
                    'text-theme-info'
                  }`}>
                    {enforcementConfig.label}
                  </p>
                </div>
                <div>
                  <span className="text-sm font-medium text-theme-muted">Created</span>
                  <p className="text-theme-primary mt-1">{formatDate(policy.created_at)}</p>
                </div>
                <div>
                  <span className="text-sm font-medium text-theme-muted">Last Updated</span>
                  <p className="text-theme-primary mt-1">{formatDate(policy.updated_at)}</p>
                </div>
              </div>

              {policy.description && (
                <div>
                  <span className="text-sm font-medium text-theme-muted">Description</span>
                  <p className="text-theme-primary mt-1">{policy.description}</p>
                </div>
              )}
            </div>
          </Card>

          <Card className="p-6">
            <h2 className="text-lg font-semibold text-theme-primary mb-4">License Restrictions</h2>
            <div className="space-y-3">
              <RestrictionRow
                label="Block all copyleft licenses"
                enabled={policy.block_copyleft}
              />
              <RestrictionRow
                label="Block strong copyleft (GPL)"
                enabled={policy.block_strong_copyleft}
              />
              <RestrictionRow
                label="Block network copyleft (AGPL)"
                enabled={policy.block_network_copyleft}
              />
              <RestrictionRow
                label="Block unknown licenses"
                enabled={policy.block_unknown}
              />
              <RestrictionRow
                label="Require OSI-approved licenses"
                enabled={policy.require_osi_approved}
              />
              <RestrictionRow
                label="Require attribution notices"
                enabled={policy.require_attribution}
              />
            </div>
          </Card>
        </div>

        {/* Allowed Licenses */}
        {policy.allowed_licenses && policy.allowed_licenses.length > 0 && (
          <Card className="p-6">
            <div className="flex items-center gap-2 mb-4">
              <CheckCircle className="w-5 h-5 text-theme-success" />
              <h2 className="text-lg font-semibold text-theme-primary">
                Allowed Licenses ({policy.allowed_licenses.length})
              </h2>
            </div>
            <div className="flex flex-wrap gap-2">
              {policy.allowed_licenses.map((license) => (
                <span
                  key={license}
                  className="px-3 py-1 rounded-full bg-theme-success/10 text-theme-success text-sm font-medium"
                >
                  {license}
                </span>
              ))}
            </div>
          </Card>
        )}

        {/* Denied Licenses */}
        {policy.denied_licenses && policy.denied_licenses.length > 0 && (
          <Card className="p-6">
            <div className="flex items-center gap-2 mb-4">
              <XCircle className="w-5 h-5 text-theme-error" />
              <h2 className="text-lg font-semibold text-theme-primary">
                Denied Licenses ({policy.denied_licenses.length})
              </h2>
            </div>
            <div className="flex flex-wrap gap-2">
              {policy.denied_licenses.map((license) => (
                <span
                  key={license}
                  className="px-3 py-1 rounded-full bg-theme-error/10 text-theme-error text-sm font-medium"
                >
                  {license}
                </span>
              ))}
            </div>
          </Card>
        )}

        {/* Exception Packages */}
        {policy.exception_packages && policy.exception_packages.length > 0 && (
          <Card className="p-6">
            <div className="flex items-center gap-2 mb-4">
              <Shield className="w-5 h-5 text-theme-warning" />
              <h2 className="text-lg font-semibold text-theme-primary">
                Exception Packages ({policy.exception_packages.length})
              </h2>
            </div>
            <div className="space-y-3">
              {policy.exception_packages.map((exception, index) => (
                <div
                  key={index}
                  className="p-3 rounded-lg bg-theme-warning/10 border border-theme-warning/30"
                >
                  <div className="flex items-start justify-between">
                    <div>
                      <p className="font-medium text-theme-primary">{exception.package}</p>
                      <p className="text-sm text-theme-secondary">License: {exception.license}</p>
                      <p className="text-sm text-theme-tertiary mt-1">{exception.reason}</p>
                    </div>
                    {exception.expires_at && (
                      <span className="text-xs text-theme-muted">
                        Expires: {formatDate(exception.expires_at)}
                      </span>
                    )}
                  </div>
                </div>
              ))}
            </div>
          </Card>
        )}

        {/* Violation Count */}
        {typeof policy.violation_count === 'number' && policy.violation_count > 0 && (
          <div className="flex items-start gap-3 p-4 rounded-lg bg-theme-warning/10 border border-theme-warning/30">
            <AlertTriangle className="w-5 h-5 text-theme-warning flex-shrink-0 mt-0.5" />
            <div>
              <p className="font-medium text-theme-primary">
                {policy.violation_count} open violation{policy.violation_count > 1 ? 's' : ''}
              </p>
              <p className="text-sm text-theme-secondary mt-1">
                There are active violations detected by this policy.{' '}
                <button
                  onClick={() => navigate('/app/supply-chain/licenses/violations')}
                  className="text-theme-primary hover:underline"
                >
                  View violations
                </button>
              </p>
            </div>
          </div>
        )}
      </div>

      {ConfirmationDialog}
    </PageContainer>
  );
};

interface RestrictionRowProps {
  label: string;
  enabled?: boolean;
}

const RestrictionRow: React.FC<RestrictionRowProps> = ({ label, enabled }) => (
  <div className="flex items-center justify-between py-2 border-b border-theme last:border-0">
    <span className="text-sm text-theme-primary">{label}</span>
    {enabled ? (
      <CheckCircle className="w-5 h-5 text-theme-success" />
    ) : (
      <XCircle className="w-5 h-5 text-theme-muted" />
    )}
  </div>
);

export default LicensePolicyDetailPage;

import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { DataTable } from '@/shared/components/ui/DataTable';
import { Badge } from '@/shared/components/ui/Badge';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { Plus, Shield, Eye, Edit, Trash2 } from 'lucide-react';
import { useLicensePolicies, useDeleteLicensePolicy, useToggleLicensePolicyActive } from '../hooks/useLicenseCompliance';

export const LicensePoliciesPage: React.FC = () => {
  const navigate = useNavigate();
  const { showNotification } = useNotifications();
  const { confirm, ConfirmationDialog } = useConfirmation();
  const [currentPage, setCurrentPage] = useState(1);
  const perPage = 25;

  const { data, isLoading, refetch } = useLicensePolicies({
    page: currentPage,
    per_page: perPage,
  });

  const deleteMutation = useDeleteLicensePolicy();
  const toggleActiveMutation = useToggleLicensePolicyActive();

  const handleDelete = (id: string, name: string) => {
    confirm({
      title: 'Delete License Policy',
      message: `Are you sure you want to delete "${name}"? This action cannot be undone.`,
      confirmLabel: 'Delete',
      variant: 'danger',
      onConfirm: async () => {
        try {
          await deleteMutation.mutateAsync(id);
          showNotification('License policy deleted successfully', 'success');
          refetch();
        } catch (err) {
          showNotification(
            err instanceof Error ? err.message : 'Failed to delete policy',
            'error'
          );
        }
      },
    });
  };

  const handleToggleActive = async (id: string, isActive: boolean) => {
    try {
      await toggleActiveMutation.mutateAsync({ id, isActive: !isActive });
      showNotification(
        `Policy ${isActive ? 'deactivated' : 'activated'} successfully`,
        'success'
      );
      refetch();
    } catch (err) {
      showNotification(
        err instanceof Error ? err.message : 'Failed to update policy',
        'error'
      );
    }
  };

  const getPolicyTypeBadge = (type: string) => {
    const variants: Record<string, 'info' | 'warning' | 'primary'> = {
      allowlist: 'info',
      denylist: 'warning',
      hybrid: 'primary',
    };
    return <Badge variant={variants[type] || 'default'}>{type}</Badge>;
  };

  const getEnforcementBadge = (level: string) => {
    const variants: Record<string, 'success' | 'warning' | 'danger'> = {
      log: 'success',
      warn: 'warning',
      block: 'danger',
    };
    return <Badge variant={variants[level] || 'default'}>{level}</Badge>;
  };

  const columns = [
    {
      key: 'name',
      header: 'Name',
      render: (policy: any) => (
        <div className="font-medium text-theme-primary">{policy.name}</div>
      ),
    },
    {
      key: 'policy_type',
      header: 'Type',
      render: (policy: any) => getPolicyTypeBadge(policy.policy_type),
    },
    {
      key: 'enforcement_level',
      header: 'Enforcement',
      render: (policy: any) => getEnforcementBadge(policy.enforcement_level),
    },
    {
      key: 'is_active',
      header: 'Active',
      render: (policy: any) => (
        <label className="relative inline-flex items-center cursor-pointer">
          <input
            type="checkbox"
            checked={policy.is_active}
            onChange={() => handleToggleActive(policy.id, policy.is_active)}
            className="sr-only peer"
          />
          <div className="w-11 h-6 bg-theme-surface-tertiary peer-focus:outline-none peer-focus:ring-4 peer-focus:ring-theme-interactive-primary/20 rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-theme after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-theme-interactive-primary"></div>
        </label>
      ),
    },
    {
      key: 'copyleft_rules',
      header: 'Copyleft Rules',
      render: (policy: any) => (
        <div className="flex gap-2">
          {policy.block_copyleft && (
            <Badge variant="warning" size="xs">Block Copyleft</Badge>
          )}
          {policy.block_strong_copyleft && (
            <Badge variant="danger" size="xs">Block Strong</Badge>
          )}
          {!policy.block_copyleft && !policy.block_strong_copyleft && (
            <span className="text-theme-tertiary text-sm">None</span>
          )}
        </div>
      ),
    },
    {
      key: 'actions',
      header: 'Actions',
      render: (policy: any) => (
        <div className="flex items-center gap-2" onClick={(e) => e.stopPropagation()}>
          <button
            onClick={(e) => {
              e.stopPropagation();
              navigate(`/app/supply-chain/licenses/policies/${policy.id}`);
            }}
            className="p-1.5 text-theme-secondary hover:text-theme-primary hover:bg-theme-surface-secondary rounded"
            title="View details"
          >
            <Eye className="w-4 h-4" />
          </button>
          <button
            onClick={(e) => {
              e.stopPropagation();
              navigate(`/app/supply-chain/licenses/policies/${policy.id}/edit`);
            }}
            className="p-1.5 text-theme-secondary hover:text-theme-primary hover:bg-theme-surface-secondary rounded"
            title="Edit policy"
          >
            <Edit className="w-4 h-4" />
          </button>
          <button
            onClick={(e) => {
              e.stopPropagation();
              handleDelete(policy.id, policy.name);
            }}
            className="p-1.5 text-theme-secondary hover:text-theme-error hover:bg-theme-error/10 rounded"
            title="Delete policy"
          >
            <Trash2 className="w-4 h-4" />
          </button>
        </div>
      ),
    },
  ];

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'Supply Chain', href: '/app/supply-chain' },
    { label: 'License Policies' },
  ];

  const actions = [
    {
      id: 'create',
      label: 'Create Policy',
      onClick: () => navigate('/app/supply-chain/licenses/policies/new'),
      variant: 'primary' as const,
      icon: Plus,
    },
  ];

  return (
    <PageContainer
      title="License Policies"
      description="Manage license compliance policies and enforcement rules"
      breadcrumbs={breadcrumbs}
      actions={actions}
    >
      <div className="card-theme-elevated">
        <DataTable
          columns={columns}
          data={data?.policies || []}
          loading={isLoading}
          pagination={data?.pagination || undefined}
          onPageChange={setCurrentPage}
          onRowClick={(policy) => navigate(`/app/supply-chain/licenses/policies/${policy.id}`)}
          emptyState={{
            icon: Shield,
            title: 'No license policies',
            description: 'Create your first license policy to enforce compliance rules.',
            action: {
              label: 'Create Policy',
              onClick: () => navigate('/app/supply-chain/licenses/policies/new'),
            },
          }}
        />
      </div>
      {ConfirmationDialog}
    </PageContainer>
  );
};

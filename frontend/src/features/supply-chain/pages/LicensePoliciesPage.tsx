import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { DataTable } from '@/shared/components/ui/DataTable';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { Plus, Shield } from 'lucide-react';
import { useLicensePolicies, useDeleteLicensePolicy, useToggleLicensePolicyActive } from '../hooks/useLicenseCompliance';

export const LicensePoliciesPage: React.FC = () => {
  const navigate = useNavigate();
  const [currentPage, setCurrentPage] = useState(1);
  const perPage = 25;

  const { data, isLoading } = useLicensePolicies({
    page: currentPage,
    per_page: perPage,
  });

  const deleteMutation = useDeleteLicensePolicy();
  const toggleActiveMutation = useToggleLicensePolicyActive();

  const handleDelete = async (id: string) => {
    if (window.confirm('Are you sure you want to delete this license policy?')) {
      await deleteMutation.mutateAsync(id);
    }
  };

  const handleToggleActive = async (id: string, isActive: boolean) => {
    await toggleActiveMutation.mutateAsync({ id, isActive: !isActive });
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
        <div className="flex gap-2">
          <Button
            variant="secondary"
            size="xs"
            onClick={() => navigate(`/app/supply-chain/licenses/policies/${policy.id}/edit`)}
          >
            Edit
          </Button>
          <Button
            variant="danger"
            size="xs"
            onClick={() => handleDelete(policy.id)}
          >
            Delete
          </Button>
        </div>
      ),
    },
  ];

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'Supply Chain', href: '/app/supply-chain' },
    { label: 'License Policies' },
  ];

  return (
    <PageContainer
      title="License Policies"
      description="Manage license compliance policies and enforcement rules"
      breadcrumbs={breadcrumbs}
      actions={[
        {
          id: 'create-policy',
          label: 'Create Policy',
          onClick: () => alert('License policy creation form coming soon.'),
          variant: 'primary',
          icon: Plus,
        },
      ]}
    >
      <div className="card-theme-elevated">
        <DataTable
          columns={columns}
          data={data?.policies || []}
          loading={isLoading}
          pagination={data?.pagination}
          onPageChange={setCurrentPage}
          emptyState={{
            icon: Shield,
            title: 'No license policies',
            description: 'Create your first license policy to enforce compliance rules',
            action: {
              label: 'Create Policy',
              onClick: () => alert('License policy creation form coming soon.'),
            },
          }}
        />
      </div>
    </PageContainer>
  );
};

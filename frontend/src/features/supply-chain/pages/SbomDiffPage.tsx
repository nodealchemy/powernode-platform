import React from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { ArrowLeft, GitCompare } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import ErrorAlert from '@/shared/components/ui/ErrorAlert';
import { SbomDiffViewer } from '../components/sbom/SbomDiffViewer';
import { useSbomDiff } from '../hooks/useSboms';
import { formatDateTime } from '@/shared/utils/formatters';

export const SbomDiffPage: React.FC = () => {
  const { id, diffId } = useParams<{ id: string; diffId: string }>();
  const navigate = useNavigate();
  const { diff, loading, error } = useSbomDiff(id || null, diffId || null);

  if (loading) {
    return (
      <div className="flex justify-center items-center min-h-screen">
        <LoadingSpinner size="lg" />
      </div>
    );
  }

  if (error || !diff) {
    return (
      <PageContainer
        title="SBOM Diff"
        breadcrumbs={[
          { label: 'Dashboard', href: '/app' },
          { label: 'Supply Chain', href: '/app/supply-chain' },
          { label: 'SBOMs', href: '/app/supply-chain/sboms' },
          { label: 'Diff' },
        ]}
      >
        <ErrorAlert message={error || 'Diff not found'} />
      </PageContainer>
    );
  }

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'Supply Chain', href: '/app/supply-chain' },
    { label: 'SBOMs', href: '/app/supply-chain/sboms' },
    { label: 'SBOM', href: `/app/supply-chain/sboms/${id}` },
    { label: 'Diff' },
  ];

  const actions = [
    {
      id: 'back',
      label: 'Back to SBOM',
      onClick: () => navigate(`/app/supply-chain/sboms/${id}`),
      variant: 'secondary' as const,
      icon: ArrowLeft,
    },
  ];


  return (
    <PageContainer
      title="SBOM Comparison"
      description={`Created ${formatDateTime(diff.created_at)}`}
      breadcrumbs={breadcrumbs}
      actions={actions}
    >
      <div className="mb-6 flex items-center gap-3">
        <GitCompare className="w-5 h-5 text-theme-interactive-primary" />
        <span className="text-theme-secondary">
          Comparing changes between two SBOM versions
        </span>
      </div>

      <SbomDiffViewer diff={diff} />
    </PageContainer>
  );
};

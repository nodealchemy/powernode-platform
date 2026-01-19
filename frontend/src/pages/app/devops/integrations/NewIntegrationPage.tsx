import { useNavigate } from 'react-router-dom';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { IntegrationWizard } from '@/features/devops/integrations/components/IntegrationWizard/IntegrationWizard';

export function NewIntegrationPage() {
  const navigate = useNavigate();

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'DevOps', href: '/app/devops' },
    { label: 'Integrations', href: '/app/devops/integrations' },
    { label: 'Add Integration' }
  ];

  return (
    <PageContainer
      title="Add Integration"
      description="Set up a new integration for your account"
      breadcrumbs={breadcrumbs}
      actions={[
        {
          label: 'Cancel',
          onClick: () => navigate('/app/devops/integrations'),
          variant: 'secondary',
        },
      ]}
    >
      <IntegrationWizard />
    </PageContainer>
  );
}

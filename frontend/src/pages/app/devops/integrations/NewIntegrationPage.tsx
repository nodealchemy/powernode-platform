import { useNavigate } from 'react-router-dom';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { IntegrationWizard } from '@/features/devops/integrations/components/IntegrationWizard/IntegrationWizard';

export function NewIntegrationPage() {
  const navigate = useNavigate();

  return (
    <PageContainer
      title="Add Integration"
      description="Set up a new integration for your account"
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

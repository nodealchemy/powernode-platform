import React, { useState, useCallback } from 'react';
import { PageContainer, type PageAction } from '@/shared/components/layout/PageContainer';
import { AiProvidersPage as AiProvidersComponent } from '@/features/ai/providers/components/AiProvidersPage';

export const AIProvidersPage: React.FC = () => {
  const [actions, setActions] = useState<PageAction[]>([]);

  const handleActionsReady = useCallback((newActions: PageAction[]) => {
    setActions(newActions);
  }, []);

  return (
    <PageContainer
      title="AI Providers"
      description="Manage AI provider integrations"
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'AI', href: '/app/ai' },
        { label: 'Providers' }
      ]}
      actions={actions}
    >
      <AiProvidersComponent onActionsReady={handleActionsReady} />
    </PageContainer>
  );
};

export default AIProvidersPage;
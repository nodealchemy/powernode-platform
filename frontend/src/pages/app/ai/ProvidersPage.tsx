import React, { useState } from 'react';
import { PageContainer, type PageAction } from '@/shared/components/layout/PageContainer';
import { AiProvidersPage as AiProvidersContent } from '@/features/ai/providers/components/AiProvidersPage';

/** AI → Platform → Providers (fc-43: formerly the Infrastructure hub's default tab). */
export const ProvidersPage: React.FC = () => {
  const [actions, setActions] = useState<PageAction[]>([]);

  return (
    <PageContainer
      title="Providers"
      description="AI providers and their credentials"
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'AI', href: '/app/ai' },
        { label: 'Providers' },
      ]}
      actions={actions}
    >
      <AiProvidersContent onActionsReady={setActions} />
    </PageContainer>
  );
};

export default ProvidersPage;

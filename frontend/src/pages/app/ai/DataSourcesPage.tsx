import React, { useState } from 'react';
import { PageContainer, type PageAction } from '@/shared/components/layout/PageContainer';
import { AiDataSourcesPage as AiDataSourcesContent } from '@/features/ai/data-sources/components/AiDataSourcesPage';

/** AI → Platform → Data Sources (fc-43: formerly an Infrastructure hub tab). */
export const DataSourcesPage: React.FC = () => {
  const [actions, setActions] = useState<PageAction[]>([]);

  return (
    <PageContainer
      title="Data Sources"
      description="External data sources agents can query"
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'AI', href: '/app/ai' },
        { label: 'Data Sources' },
      ]}
      actions={actions}
    >
      <AiDataSourcesContent onActionsReady={setActions} />
    </PageContainer>
  );
};

export default DataSourcesPage;

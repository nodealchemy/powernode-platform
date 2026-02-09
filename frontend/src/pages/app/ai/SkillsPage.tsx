import React, { useState, useCallback } from 'react';
import { PageContainer, type PageAction } from '@/shared/components/layout/PageContainer';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';
import { SkillsPage as SkillsComponent } from '@/features/ai/skills/SkillsPage';

export const SkillsContent: React.FC = () => {
  usePageWebSocket({
    pageType: 'ai',
    onDataUpdate: () => {},
  });

  return <SkillsComponent />;
};

export const SkillsPage: React.FC = () => {
  const [actions, setActions] = useState<PageAction[]>([]);

  usePageWebSocket({
    pageType: 'ai',
    onDataUpdate: () => {},
  });

  const handleActionsReady = useCallback((newActions: PageAction[]) => {
    setActions(newActions);
  }, []);

  return (
    <PageContainer
      title="AI Skills"
      description="Domain-specific skill bundles for AI agents with commands and MCP connectors"
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'AI', href: '/app/ai' },
        { label: 'Skills' },
      ]}
      actions={actions}
    >
      <SkillsComponent onActionsReady={handleActionsReady} />
    </PageContainer>
  );
};

export default SkillsPage;

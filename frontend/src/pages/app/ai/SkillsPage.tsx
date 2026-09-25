import React, { useState, useCallback } from 'react';
import { PageContainer, type PageAction } from '@/shared/components/layout/PageContainer';
import { SkillsPage as SkillsComponent } from '@/features/ai/skills/SkillsPage';

interface SkillsContentProps {
  onActionsReady?: (actions: PageAction[]) => void;
}

export const SkillsContent: React.FC<SkillsContentProps> = ({ onActionsReady }) => {

  return <SkillsComponent onActionsReady={onActionsReady} />;
};

export const SkillsPage: React.FC = () => {
  const [actions, setActions] = useState<PageAction[]>([]);


  const handleActionsReady = useCallback((newActions: PageAction[]) => {
    setActions(newActions);
  }, []);

  return (
    <PageContainer
      title="Skills"
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

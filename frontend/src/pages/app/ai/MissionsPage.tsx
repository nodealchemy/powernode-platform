import React, { useState, useEffect, useCallback } from 'react';
import { useLocation } from 'react-router-dom';
import { Rocket, Code2 } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import type { PageAction } from '@/shared/components/layout/PageContainer';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { MissionsContent } from '@/features/missions/pages/MissionsPage';
import { CodeFactoryContent } from '@/features/ai/code-factory/pages/CodeFactoryPage';

const tabs = [
  { id: 'missions', label: 'Missions', icon: <Rocket size={16} />, path: '/' },
  { id: 'code-factory', label: 'Code Factory', icon: <Code2 size={16} />, path: '/code-factory' },
];

export const MissionsPageWrapper: React.FC = () => {
  const location = useLocation();
  const [actions, setActions] = useState<PageAction[]>([]);

  const getActiveTab = () => {
    const path = location.pathname;
    if (path.includes('/missions/code-factory')) return 'code-factory';
    return 'missions';
  };

  const [activeTab, setActiveTab] = useState(getActiveTab());

  useEffect(() => {
    const newTab = getActiveTab();
    if (newTab !== activeTab) setActiveTab(newTab);
  }, [location.pathname]);

  // Clear actions on tab change
  useEffect(() => {
    setActions([]);
  }, [activeTab]);

  const handleActionsReady = useCallback((newActions: PageAction[]) => {
    setActions(newActions);
  }, []);

  const getBreadcrumbs = () => {
    const base: Array<{ label: string; href?: string }> = [
      { label: 'Dashboard', href: '/app' },
      { label: 'AI', href: '/app/ai' },
    ];
    if (activeTab === 'missions') {
      base.push({ label: 'Missions' });
    } else {
      base.push({ label: 'Missions', href: '/app/ai/missions' });
      base.push({ label: 'Code Factory' });
    }
    return base;
  };

  return (
    <PageContainer
      title="Missions"
      description="AI-assisted development missions and code factory"
      breadcrumbs={getBreadcrumbs()}
      actions={actions}
    >
      <TabContainer
        tabs={tabs}
        activeTab={activeTab}
        onTabChange={setActiveTab}
        basePath="/app/ai/missions"
        variant="underline"
        className="mb-6"
      >
        <TabPanel tabId="missions" activeTab={activeTab}>
          <MissionsContent onActionsReady={handleActionsReady} />
        </TabPanel>
        <TabPanel tabId="code-factory" activeTab={activeTab}>
          <CodeFactoryContent basePath="/app/ai/missions/code-factory" onActionsReady={handleActionsReady} />
        </TabPanel>
      </TabContainer>
    </PageContainer>
  );
};

export default MissionsPageWrapper;

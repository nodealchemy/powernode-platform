import React, { useState, useEffect } from 'react';
import { useLocation } from 'react-router-dom';
import { Workflow, Server } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { PipelinesPage } from '@/pages/app/devops/PipelinesPage';
import { RunnersPage as AiPipelinesRunnersPage } from '@/features/devops/pipelines';

const tabs = [
  { id: 'pipelines', label: 'Pipelines', icon: <Workflow size={16} />, path: '/' },
  { id: 'runners', label: 'Runners', icon: <Server size={16} />, path: '/runners' },
];

export const CiCdPage: React.FC = () => {
  const location = useLocation();

  const getActiveTab = () => {
    const path = location.pathname;
    if (path.includes('/ci-cd/runners')) return 'runners';
    return 'pipelines';
  };

  const [activeTab, setActiveTab] = useState(getActiveTab());

  useEffect(() => {
    const newTab = getActiveTab();
    if (newTab !== activeTab) setActiveTab(newTab);
  }, [location.pathname]);

  const getBreadcrumbs = () => {
    const base: Array<{ label: string; href?: string }> = [
      { label: 'Dashboard', href: '/app' },
      { label: 'DevOps', href: '/app/devops' },
    ];
    if (activeTab === 'pipelines') {
      base.push({ label: 'CI/CD' });
    } else {
      base.push({ label: 'CI/CD', href: '/app/devops/ci-cd' });
      const activeTabInfo = tabs.find(t => t.id === activeTab);
      if (activeTabInfo) base.push({ label: activeTabInfo.label });
    }
    return base;
  };

  return (
    <PageContainer
      title="CI/CD"
      description="Pipelines and runner management"
      breadcrumbs={getBreadcrumbs()}
    >
      <TabContainer
        tabs={tabs}
        activeTab={activeTab}
        onTabChange={setActiveTab}
        basePath="/app/devops/ci-cd"
        variant="underline"
        className="mb-6"
      >
        <TabPanel tabId="pipelines" activeTab={activeTab}>
          <PipelinesPage />
        </TabPanel>
        <TabPanel tabId="runners" activeTab={activeTab}>
          <AiPipelinesRunnersPage />
        </TabPanel>
      </TabContainer>
    </PageContainer>
  );
};

export default CiCdPage;

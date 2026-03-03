import React, { useState, useEffect } from 'react';
import { useLocation } from 'react-router-dom';
import { LayoutDashboard, GitBranch, FolderGit2 } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { DevOpsOverviewPage } from '@/pages/app/devops/DevOpsOverviewPage';
import { GitProvidersPage } from '@/pages/app/devops/GitProvidersPage';
import { RepositoriesPage } from '@/pages/app/devops/RepositoriesPage';

const tabs = [
  { id: 'overview', label: 'Overview', icon: <LayoutDashboard size={16} />, path: '/' },
  { id: 'providers', label: 'Providers', icon: <GitBranch size={16} />, path: '/providers' },
  { id: 'repositories', label: 'Repositories', icon: <FolderGit2 size={16} />, path: '/repositories' },
];

export const SourceControlPage: React.FC = () => {
  const location = useLocation();

  const getActiveTab = () => {
    const path = location.pathname;
    if (path.includes('/source-control/providers')) return 'providers';
    if (path.includes('/source-control/repositories')) return 'repositories';
    return 'overview';
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
    if (activeTab === 'overview') {
      base.push({ label: 'Source Control' });
    } else {
      base.push({ label: 'Source Control', href: '/app/devops/source-control' });
      const activeTabInfo = tabs.find(t => t.id === activeTab);
      if (activeTabInfo) base.push({ label: activeTabInfo.label });
    }
    return base;
  };

  return (
    <PageContainer
      title="Source Control"
      description="Git providers and repository management"
      breadcrumbs={getBreadcrumbs()}
    >
      <TabContainer
        tabs={tabs}
        activeTab={activeTab}
        onTabChange={setActiveTab}
        basePath="/app/devops/source-control"
        variant="underline"
        className="mb-6"
      >
        <TabPanel tabId="overview" activeTab={activeTab}>
          <DevOpsOverviewPage />
        </TabPanel>
        <TabPanel tabId="providers" activeTab={activeTab}>
          <GitProvidersPage />
        </TabPanel>
        <TabPanel tabId="repositories" activeTab={activeTab}>
          <RepositoriesPage />
        </TabPanel>
      </TabContainer>
    </PageContainer>
  );
};

export default SourceControlPage;

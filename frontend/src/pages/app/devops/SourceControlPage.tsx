import React, { useState, useEffect, useCallback } from 'react';
import { useLocation } from 'react-router-dom';
import { GitBranch, FolderGit2 } from 'lucide-react';
import { PageContainer, type PageAction } from '@/shared/components/layout/PageContainer';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { GitProvidersPage } from '@/pages/app/devops/GitProvidersPage';
import { RepositoriesPage } from '@/pages/app/devops/RepositoriesPage';

// Providers is the default tab: the bare /app/devops/source-control URL opens it.
const tabs = [
  { id: 'providers', label: 'Git Providers', icon: <GitBranch size={16} />, path: '/providers' },
  { id: 'repositories', label: 'Repositories', icon: <FolderGit2 size={16} />, path: '/repositories' },
];

export const SourceControlPage: React.FC = () => {
  const location = useLocation();

  const getActiveTab = () => {
    if (location.pathname.includes('/source-control/repositories')) return 'repositories';
    return 'providers';
  };

  const [activeTab, setActiveTab] = useState(getActiveTab());
  const [actions, setActions] = useState<PageAction[]>([]);

  useEffect(() => {
    const newTab = getActiveTab();
    if (newTab !== activeTab) {
      setActiveTab(newTab);
      setActions([]);
    }
  }, [location.pathname]);

  const handleTabChange = useCallback((tabId: string) => {
    setActiveTab(tabId);
    setActions([]);
  }, []);

  const handleActionsReady = useCallback((newActions: PageAction[]) => {
    setActions(newActions);
  }, []);

  const getBreadcrumbs = () => {
    const base: Array<{ label: string; href?: string }> = [
      { label: 'Dashboard', href: '/app' },
      { label: 'DevOps', href: '/app/devops' },
    ];
    if (activeTab === 'providers') {
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
      actions={actions}
    >
      <TabContainer
        tabs={tabs}
        activeTab={activeTab}
        onTabChange={handleTabChange}
        basePath="/app/devops/source-control"
        variant="underline"
        className="mb-6"
      >
        <TabPanel tabId="providers" activeTab={activeTab}>
          <GitProvidersPage onActionsReady={handleActionsReady} />
        </TabPanel>
        <TabPanel tabId="repositories" activeTab={activeTab}>
          <RepositoriesPage onActionsReady={handleActionsReady} />
        </TabPanel>
      </TabContainer>
    </PageContainer>
  );
};

export default SourceControlPage;

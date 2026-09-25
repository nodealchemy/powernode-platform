import React, { useState, useEffect, useCallback } from 'react';
import { useLocation } from 'react-router-dom';
import { LayoutDashboard, Workflow, Server, FileText } from 'lucide-react';
import { PageContainer, type PageAction } from '@/shared/components/layout/PageContainer';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { CiCdOverviewTab } from '@/pages/app/devops/CiCdOverviewTab';
import { PipelinesPage } from '@/pages/app/devops/PipelinesPage';
import { RunnersPage as AiPipelinesRunnersPage } from '@/features/devops/pipelines';
import { TemplatesContent } from '@/pages/app/ai/DevOpsTemplatesPage';

// fc-34: the "Module Builds" tab (features/devops/module-builds) was deleted
// as a duplicate of the system extension's own Module Builds surface, which
// registers its OWN route at this same URL (/app/devops/ci-cd/module-builds)
// via featureRegistry — core must not import or reference it. React Router
// resolves that more-specific literal path ahead of this page's own
// `/devops/ci-cd/*` wildcard mount, so the URL keeps working without a tab
// entry here; the sidebar's DevOps section carries the discoverable nav link
// (registered by the extension) since it no longer lives in this tab strip.
const tabs = [
  { id: 'overview', label: 'Overview', icon: <LayoutDashboard size={16} />, path: '/' },
  { id: 'pipelines', label: 'Pipelines', icon: <Workflow size={16} />, path: '/pipelines' },
  { id: 'runners', label: 'Runners', icon: <Server size={16} />, path: '/runners' },
  { id: 'templates', label: 'Templates', icon: <FileText size={16} />, path: '/templates', permissions: ['ai.devops.read'] },
];

export const CiCdPage: React.FC = () => {
  const location = useLocation();

  const getActiveTab = () => {
    const path = location.pathname;
    if (path.includes('/ci-cd/pipelines')) return 'pipelines';
    if (path.includes('/ci-cd/runners')) return 'runners';
    if (path.includes('/ci-cd/templates')) return 'templates';
    return 'overview';
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
    if (activeTab === 'overview') {
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
      actions={actions}
    >
      <TabContainer
        tabs={tabs}
        activeTab={activeTab}
        onTabChange={handleTabChange}
        basePath="/app/devops/ci-cd"
        variant="underline"
        className="mb-6"
      >
        <TabPanel tabId="overview" activeTab={activeTab}>
          <CiCdOverviewTab />
        </TabPanel>
        <TabPanel tabId="pipelines" activeTab={activeTab}>
          <PipelinesPage onActionsReady={handleActionsReady} />
        </TabPanel>
        <TabPanel tabId="runners" activeTab={activeTab}>
          <AiPipelinesRunnersPage onActionsReady={handleActionsReady} />
        </TabPanel>
        <TabPanel tabId="templates" activeTab={activeTab}>
          <TemplatesContent onActionsReady={handleActionsReady} />
        </TabPanel>
      </TabContainer>
    </PageContainer>
  );
};

export default CiCdPage;

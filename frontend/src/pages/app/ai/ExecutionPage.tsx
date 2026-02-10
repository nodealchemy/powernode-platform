import React, { useState, useEffect, useCallback } from 'react';
import { useLocation } from 'react-router-dom';
import { RotateCcw, Activity, GitFork, FolderOutput, Radio } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { useRefreshAction } from '@/shared/hooks/useRefreshAction';
import { RalphLoopsContent } from '@/features/ai/ralph-loops/pages/RalphLoopsPage';
import { A2aTasksContent } from '@/pages/app/ai/A2aTasksPage';
import { ParallelExecutionContent } from '@/features/ai/parallel-execution/pages/ParallelExecutionPage';
import { ExecutionResourcesContent } from '@/pages/app/ai/ExecutionResourcesPage';
import { AguiContent } from '@/features/ai/agui';

const tabs = [
  { id: 'ralph-loops', label: 'Ralph Loops', icon: <RotateCcw size={16} />, path: '/' },
  { id: 'a2a-tasks', label: 'A2A Tasks', icon: <Activity size={16} />, path: '/a2a-tasks' },
  { id: 'parallel', label: 'Parallel', icon: <GitFork size={16} />, path: '/parallel' },
  { id: 'resources', label: 'Resources', icon: <FolderOutput size={16} />, path: '/resources' },
  { id: 'agui', label: 'AG-UI', icon: <Radio size={16} />, path: '/agui' },
];

export const ExecutionPage: React.FC = () => {
  const location = useLocation();

  const getActiveTab = () => {
    const path = location.pathname;
    if (path.includes('/execution/a2a-tasks')) return 'a2a-tasks';
    if (path.includes('/execution/parallel')) return 'parallel';
    if (path.includes('/execution/resources')) return 'resources';
    if (path.includes('/execution/agui')) return 'agui';
    return 'ralph-loops';
  };

  const [activeTab, setActiveTab] = useState(getActiveTab());
  const [refreshKey, setRefreshKey] = useState(0);

  useEffect(() => {
    const newTab = getActiveTab();
    if (newTab !== activeTab) setActiveTab(newTab);
  }, [location.pathname]);

  const handleRefresh = useCallback(() => {
    setRefreshKey(k => k + 1);
  }, []);

  const { refreshAction } = useRefreshAction({
    onRefresh: handleRefresh,
  });

  const getBreadcrumbs = () => {
    const base: Array<{ label: string; href?: string }> = [
      { label: 'Dashboard', href: '/app' },
      { label: 'AI', href: '/app/ai' },
    ];
    const activeTabInfo = tabs.find(t => t.id === activeTab);
    if (activeTab === 'ralph-loops') {
      base.push({ label: 'Execution' });
    } else {
      base.push({ label: 'Execution', href: '/app/ai/execution' });
      if (activeTabInfo) base.push({ label: activeTabInfo.label });
    }
    return base;
  };

  return (
    <PageContainer
      title="Execution"
      description="Monitor and manage active AI agent execution"
      breadcrumbs={getBreadcrumbs()}
      actions={[refreshAction]}
    >
      <TabContainer
        tabs={tabs}
        activeTab={activeTab}
        onTabChange={setActiveTab}
        basePath="/app/ai/execution"
        variant="underline"
        className="mb-6"
      >
        <TabPanel tabId="ralph-loops" activeTab={activeTab}>
          <RalphLoopsContent refreshKey={refreshKey} />
        </TabPanel>
        <TabPanel tabId="a2a-tasks" activeTab={activeTab}>
          <A2aTasksContent refreshKey={refreshKey} />
        </TabPanel>
        <TabPanel tabId="parallel" activeTab={activeTab}>
          <ParallelExecutionContent refreshKey={refreshKey} />
        </TabPanel>
        <TabPanel tabId="resources" activeTab={activeTab}>
          <ExecutionResourcesContent refreshKey={refreshKey} />
        </TabPanel>
        <TabPanel tabId="agui" activeTab={activeTab}>
          <AguiContent />
        </TabPanel>
      </TabContainer>
    </PageContainer>
  );
};

export default ExecutionPage;

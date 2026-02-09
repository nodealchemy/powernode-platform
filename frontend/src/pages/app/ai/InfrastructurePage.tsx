import React, { useState, useEffect } from 'react';
import { useLocation } from 'react-router-dom';
import { Brain, Server, Route } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { AiProvidersPage as AiProvidersComponent } from '@/features/ai/providers/components/AiProvidersPage';
import { McpBrowserContent } from '@/pages/app/ai/McpBrowserPage';
import { ModelRouterContent } from '@/pages/app/ai/ModelRouterPage';

const tabs = [
  { id: 'providers', label: 'Providers', icon: <Brain size={16} />, path: '/' },
  { id: 'mcp', label: 'MCP Servers', icon: <Server size={16} />, path: '/mcp' },
  { id: 'model-router', label: 'Model Router', icon: <Route size={16} />, path: '/model-router' },
];

export const InfrastructurePage: React.FC = () => {
  const location = useLocation();

  const getActiveTab = () => {
    const path = location.pathname;
    if (path.includes('/infrastructure/mcp')) return 'mcp';
    if (path.includes('/infrastructure/model-router')) return 'model-router';
    return 'providers';
  };

  const [activeTab, setActiveTab] = useState(getActiveTab());

  useEffect(() => {
    const newTab = getActiveTab();
    if (newTab !== activeTab) setActiveTab(newTab);
  }, [location.pathname]);

  const getBreadcrumbs = () => {
    const base: Array<{ label: string; href?: string }> = [
      { label: 'Dashboard', href: '/app' },
      { label: 'AI', href: '/app/ai' },
    ];
    const activeTabInfo = tabs.find(t => t.id === activeTab);
    if (activeTab === 'providers') {
      base.push({ label: 'Infrastructure' });
    } else {
      base.push({ label: 'Infrastructure', href: '/app/ai/infrastructure' });
      if (activeTabInfo) base.push({ label: activeTabInfo.label });
    }
    return base;
  };

  return (
    <PageContainer
      title="Infrastructure"
      description="Configure AI providers, MCP servers, and model routing"
      breadcrumbs={getBreadcrumbs()}
    >
      <TabContainer
        tabs={tabs}
        activeTab={activeTab}
        onTabChange={setActiveTab}
        basePath="/app/ai/infrastructure"
        variant="underline"
        className="mb-6"
      >
        <TabPanel tabId="providers" activeTab={activeTab}>
          <AiProvidersComponent />
        </TabPanel>
        <TabPanel tabId="mcp" activeTab={activeTab}>
          <McpBrowserContent />
        </TabPanel>
        <TabPanel tabId="model-router" activeTab={activeTab}>
          <ModelRouterContent />
        </TabPanel>
      </TabContainer>
    </PageContainer>
  );
};

export default InfrastructurePage;

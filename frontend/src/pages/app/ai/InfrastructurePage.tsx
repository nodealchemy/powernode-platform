import React, { useState, useEffect } from 'react';
import { useLocation } from 'react-router-dom';
import { Brain, Server, Route, AppWindow, Workflow, Key, Activity } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { AiProvidersPage as AiProvidersComponent } from '@/features/ai/providers/components/AiProvidersPage';
import { McpBrowserContent } from '@/pages/app/ai/McpBrowserPage';
import { ModelRouterContent } from '@/pages/app/ai/ModelRouterPage';
import { McpAppsContent } from '@/features/ai/mcp-apps';
import { McpStudioTab } from '@/features/ai/mcp/components/McpStudioTab';
import { McpTokensTab } from '@/features/ai/mcp-server/components/McpTokensTab';
import { McpSessionsTab } from '@/features/ai/mcp-server/components/McpSessionsTab';

const tabs = [
  { id: 'providers', label: 'Providers', icon: <Brain size={16} />, path: '/' },
  { id: 'mcp', label: 'MCP Servers', icon: <Server size={16} />, path: '/mcp' },
  { id: 'model-router', label: 'Model Router', icon: <Route size={16} />, path: '/model-router' },
  { id: 'mcp-apps', label: 'MCP Apps', icon: <AppWindow size={16} />, path: '/mcp-apps' },
  { id: 'mcp-studio', label: 'MCP Studio', icon: <Workflow size={16} />, path: '/mcp-studio' },
  { id: 'mcp-tokens', label: 'MCP Tokens', icon: <Key size={16} />, path: '/mcp-tokens' },
  { id: 'mcp-sessions', label: 'MCP Sessions', icon: <Activity size={16} />, path: '/mcp-sessions' },
];

export const InfrastructurePage: React.FC = () => {
  const location = useLocation();

  const getActiveTab = () => {
    const path = location.pathname;
    if (path.includes('/infrastructure/mcp-tokens')) return 'mcp-tokens';
    if (path.includes('/infrastructure/mcp-sessions')) return 'mcp-sessions';
    if (path.includes('/infrastructure/mcp-studio')) return 'mcp-studio';
    if (path.includes('/infrastructure/mcp-apps')) return 'mcp-apps';
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
        <TabPanel tabId="mcp-apps" activeTab={activeTab}>
          <McpAppsContent />
        </TabPanel>
        <TabPanel tabId="mcp-studio" activeTab={activeTab}>
          <McpStudioTab />
        </TabPanel>
        <TabPanel tabId="mcp-tokens" activeTab={activeTab}>
          <McpTokensTab />
        </TabPanel>
        <TabPanel tabId="mcp-sessions" activeTab={activeTab}>
          <McpSessionsTab />
        </TabPanel>
      </TabContainer>
    </PageContainer>
  );
};

export default InfrastructurePage;

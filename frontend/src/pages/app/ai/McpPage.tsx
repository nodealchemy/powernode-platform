import React, { useState, useEffect, useCallback } from 'react';
import { useLocation } from 'react-router-dom';
import { Server, AppWindow, Workflow, Activity } from 'lucide-react';
import { PageContainer, type PageAction } from '@/shared/components/layout/PageContainer';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { McpBrowserContent } from '@/pages/app/ai/McpBrowserPage';
import { McpAppsContent } from '@/features/ai/mcp-apps';
import { McpStudioTab } from '@/features/ai/mcp/components/McpStudioTab';
import { McpSessionsTab } from '@/features/ai/mcp-server/components/McpSessionsTab';

// AI → Platform → MCP (fc-43). These four were tabs of the former
// "Infrastructure" hub, a name that did not say it held MCP. Each tab is gated
// like its endpoints: McpServersController (mcp.servers.read, which the
// studio's topology also reads) and McpAppsController / Mcp::SessionsController
// (ai.agents.read).
const tabs = [
  { id: 'servers', label: 'Servers', icon: <Server size={16} />, path: '/', permissions: ['mcp.servers.read'] },
  { id: 'apps', label: 'Apps', icon: <AppWindow size={16} />, path: '/apps', permissions: ['ai.agents.read'] },
  { id: 'studio', label: 'Studio', icon: <Workflow size={16} />, path: '/studio', permissions: ['mcp.servers.read'] },
  { id: 'sessions', label: 'Sessions', icon: <Activity size={16} />, path: '/sessions', permissions: ['ai.agents.read'] },
];

export const McpPage: React.FC = () => {
  const location = useLocation();
  const { hasPermission } = usePermissions();
  const [actions, setActions] = useState<PageAction[]>([]);

  const visibleTabs = tabs.filter((t) => t.permissions.every((p) => hasPermission(p)));
  const segment = location.pathname.replace(/^\/app\/ai\/mcp/, '').split('/')[1] || '';
  const activeTab = visibleTabs.find((t) => t.path === `/${segment}`)?.id ?? visibleTabs[0]?.id ?? '';

  useEffect(() => {
    setActions([]);
  }, [activeTab]);

  const handleActionsReady = useCallback((newActions: PageAction[]) => {
    setActions(newActions);
  }, []);

  const activeTabInfo = tabs.find((t) => t.id === activeTab);
  const breadcrumbs: Array<{ label: string; href?: string }> = [
    { label: 'Dashboard', href: '/app' },
    { label: 'AI', href: '/app/ai' },
    { label: 'MCP', href: '/app/ai/mcp' },
    ...(activeTabInfo ? [{ label: activeTabInfo.label }] : []),
  ];

  return (
    <PageContainer
      title="MCP"
      description="Model Context Protocol servers, apps, studio and sessions"
      breadcrumbs={breadcrumbs}
      actions={actions}
    >
      <TabContainer tabs={tabs} activeTab={activeTab} basePath="/app/ai/mcp" variant="underline" className="mb-6">
        <TabPanel tabId="servers" activeTab={activeTab}>
          <McpBrowserContent />
        </TabPanel>
        <TabPanel tabId="apps" activeTab={activeTab}>
          <McpAppsContent />
        </TabPanel>
        <TabPanel tabId="studio" activeTab={activeTab}>
          <McpStudioTab />
        </TabPanel>
        <TabPanel tabId="sessions" activeTab={activeTab}>
          <McpSessionsTab onActionsReady={handleActionsReady} />
        </TabPanel>
      </TabContainer>
    </PageContainer>
  );
};

export default McpPage;

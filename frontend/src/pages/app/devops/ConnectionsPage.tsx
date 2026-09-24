import React, { useState, useEffect } from 'react';
import { useLocation } from 'react-router-dom';
import { Puzzle, Link2, Key } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { IntegrationsPage } from '@/pages/app/devops/integrations';
import WebhookManagementPage from '@/pages/app/devops/WebhooksPage';
import { ApiKeysPage } from '@/pages/app/devops/ApiKeysPage';

// No "File Storage" tab here — it duplicated the canonical /app/admin/storage
// page (same StorageProvidersPage component); that admin route is canonical.
const tabs = [
  { id: 'integrations', label: 'Integrations', icon: <Puzzle size={16} />, path: '/' },
  { id: 'webhooks', label: 'Webhooks', icon: <Link2 size={16} />, path: '/webhooks' },
  { id: 'api-keys', label: 'API Keys', icon: <Key size={16} />, path: '/api-keys' },
];

export const ConnectionsPage: React.FC = () => {
  const location = useLocation();

  const getActiveTab = () => {
    const path = location.pathname;
    if (path.includes('/connections/webhooks')) return 'webhooks';
    if (path.includes('/connections/api-keys')) return 'api-keys';
    return 'integrations';
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
    if (activeTab === 'integrations') {
      base.push({ label: 'Connections' });
    } else {
      base.push({ label: 'Connections', href: '/app/devops/connections' });
      const activeTabInfo = tabs.find(t => t.id === activeTab);
      if (activeTabInfo) base.push({ label: activeTabInfo.label });
    }
    return base;
  };

  return (
    <PageContainer
      title="Connections"
      description="Integrations, webhooks, and API keys"
      breadcrumbs={getBreadcrumbs()}
    >
      <TabContainer
        tabs={tabs}
        activeTab={activeTab}
        onTabChange={setActiveTab}
        basePath="/app/devops/connections"
        variant="underline"
        className="mb-6"
      >
        <TabPanel tabId="integrations" activeTab={activeTab}>
          <IntegrationsPage />
        </TabPanel>
        <TabPanel tabId="webhooks" activeTab={activeTab}>
          <WebhookManagementPage />
        </TabPanel>
        <TabPanel tabId="api-keys" activeTab={activeTab}>
          <ApiKeysPage />
        </TabPanel>
      </TabContainer>
    </PageContainer>
  );
};

export default ConnectionsPage;

import React, { useState, useEffect } from 'react';
import { useLocation } from 'react-router-dom';
import { Puzzle, Link2 } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { IntegrationsPage } from '@/pages/app/devops/integrations';
import WebhookManagementPage from '@/pages/app/devops/WebhooksPage';

// No "File Storage" tab here — it duplicated the canonical /app/admin/storage
// page (same StorageProvidersPage component); that admin route is canonical.
// API Keys has its own DevOps nav item and route (/app/devops/api-keys).
const tabs = [
  { id: 'integrations', label: 'Integrations', icon: <Puzzle size={16} />, path: '/' },
  { id: 'webhook-endpoints', label: 'Webhook endpoints', icon: <Link2 size={16} />, path: '/webhook-endpoints' },
];

export const IntegrationsWebhooksPage: React.FC = () => {
  const location = useLocation();

  const getActiveTab = () =>
    location.pathname.includes('/integrations/webhook-endpoints') ? 'webhook-endpoints' : 'integrations';

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
      base.push({ label: 'Integrations & Webhooks' });
    } else {
      base.push({ label: 'Integrations & Webhooks', href: '/app/devops/integrations' });
      const activeTabInfo = tabs.find(t => t.id === activeTab);
      if (activeTabInfo) base.push({ label: activeTabInfo.label });
    }
    return base;
  };

  return (
    <PageContainer
      title="Integrations & Webhooks"
      description="Integrations and webhook endpoints"
      breadcrumbs={getBreadcrumbs()}
    >
      <TabContainer
        tabs={tabs}
        activeTab={activeTab}
        onTabChange={setActiveTab}
        basePath="/app/devops/integrations"
        variant="underline"
        className="mb-6"
      >
        <TabPanel tabId="integrations" activeTab={activeTab}>
          <IntegrationsPage />
        </TabPanel>
        <TabPanel tabId="webhook-endpoints" activeTab={activeTab}>
          <WebhookManagementPage />
        </TabPanel>
      </TabContainer>
    </PageContainer>
  );
};

export default IntegrationsWebhooksPage;

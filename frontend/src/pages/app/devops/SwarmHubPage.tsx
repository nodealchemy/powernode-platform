import React, { useState, useEffect } from 'react';
import { useLocation } from 'react-router-dom';
import { Server, Layers, Boxes, Network, Lock, Rocket } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { ClusterProvider } from '@/features/devops/swarm/context/ClusterContext';
import { SwarmClustersPage } from '@/features/devops/swarm/pages/SwarmClustersPage';
import { SwarmServicesPage } from '@/features/devops/swarm/pages/SwarmServicesPage';
import { SwarmStacksPage } from '@/features/devops/swarm/pages/SwarmStacksPage';
import { SwarmNetworksPage } from '@/features/devops/swarm/pages/SwarmNetworksPage';
import { SwarmSecretsPage } from '@/features/devops/swarm/pages/SwarmSecretsPage';
import { SwarmDeploymentsPage } from '@/features/devops/swarm/pages/SwarmDeploymentsPage';
import { SwarmHealthPage } from '@/features/devops/swarm/pages/SwarmHealthPage';

const tabs = [
  { id: 'clusters', label: 'Clusters', icon: <Server size={16} />, path: '/' },
  { id: 'services', label: 'Services', icon: <Layers size={16} />, path: '/services' },
  { id: 'stacks', label: 'Stacks', icon: <Boxes size={16} />, path: '/stacks' },
  { id: 'networks', label: 'Networks', icon: <Network size={16} />, path: '/networks' },
  { id: 'secrets', label: 'Secrets', icon: <Lock size={16} />, path: '/secrets' },
  { id: 'operations', label: 'Operations', icon: <Rocket size={16} />, path: '/operations' },
];

export const SwarmHubPage: React.FC = () => {
  const location = useLocation();

  const getActiveTab = () => {
    const path = location.pathname;
    if (path.includes('/swarm/services')) return 'services';
    if (path.includes('/swarm/stacks')) return 'stacks';
    if (path.includes('/swarm/networks')) return 'networks';
    if (path.includes('/swarm/secrets')) return 'secrets';
    if (path.includes('/swarm/operations')) return 'operations';
    return 'clusters';
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
    if (activeTab === 'clusters') {
      base.push({ label: 'Swarm' });
    } else {
      base.push({ label: 'Swarm', href: '/app/devops/swarm' });
      const activeTabInfo = tabs.find(t => t.id === activeTab);
      if (activeTabInfo) base.push({ label: activeTabInfo.label });
    }
    return base;
  };

  return (
    <ClusterProvider>
      <PageContainer
        title="Swarm"
        description="Docker Swarm clusters, services, stacks, and operations"
        breadcrumbs={getBreadcrumbs()}
      >
        <TabContainer
          tabs={tabs}
          activeTab={activeTab}
          onTabChange={setActiveTab}
          basePath="/app/devops/swarm"
          variant="underline"
          className="mb-6"
        >
          <TabPanel tabId="clusters" activeTab={activeTab}>
            <SwarmClustersPage />
          </TabPanel>
          <TabPanel tabId="services" activeTab={activeTab}>
            <SwarmServicesPage />
          </TabPanel>
          <TabPanel tabId="stacks" activeTab={activeTab}>
            <SwarmStacksPage />
          </TabPanel>
          <TabPanel tabId="networks" activeTab={activeTab}>
            <SwarmNetworksPage />
          </TabPanel>
          <TabPanel tabId="secrets" activeTab={activeTab}>
            <SwarmSecretsPage />
          </TabPanel>
          <TabPanel tabId="operations" activeTab={activeTab}>
            <div className="space-y-8">
              <SwarmDeploymentsPage />
              <SwarmHealthPage />
            </div>
          </TabPanel>
        </TabContainer>
      </PageContainer>
    </ClusterProvider>
  );
};

export default SwarmHubPage;

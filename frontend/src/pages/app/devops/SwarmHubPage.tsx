import React, { useState, useEffect, useCallback } from 'react';
import { useLocation } from 'react-router-dom';
import { Server, Layers, Boxes, Network, Lock, Rocket } from 'lucide-react';
import { PageContainer, type PageAction } from '@/shared/components/layout/PageContainer';
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
  { id: 'stacks', label: 'Stacks', icon: <Boxes size={16} />, path: '/stacks' },
  { id: 'services', label: 'Services', icon: <Layers size={16} />, path: '/services' },
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
        actions={actions}
      >
        <TabContainer
          tabs={tabs}
          activeTab={activeTab}
          onTabChange={handleTabChange}
          basePath="/app/devops/swarm"
          variant="underline"
          className="mb-6"
        >
          <TabPanel tabId="clusters" activeTab={activeTab}>
            <SwarmClustersPage onActionsReady={handleActionsReady} />
          </TabPanel>
          <TabPanel tabId="services" activeTab={activeTab}>
            <SwarmServicesPage onActionsReady={handleActionsReady} />
          </TabPanel>
          <TabPanel tabId="stacks" activeTab={activeTab}>
            <SwarmStacksPage onActionsReady={handleActionsReady} />
          </TabPanel>
          <TabPanel tabId="networks" activeTab={activeTab}>
            <SwarmNetworksPage onActionsReady={handleActionsReady} />
          </TabPanel>
          <TabPanel tabId="secrets" activeTab={activeTab}>
            <SwarmSecretsPage onActionsReady={handleActionsReady} />
          </TabPanel>
          <TabPanel tabId="operations" activeTab={activeTab}>
            <div className="space-y-8">
              <SwarmDeploymentsPage onActionsReady={handleActionsReady} />
              <SwarmHealthPage />
            </div>
          </TabPanel>
        </TabContainer>
      </PageContainer>
    </ClusterProvider>
  );
};

export default SwarmHubPage;

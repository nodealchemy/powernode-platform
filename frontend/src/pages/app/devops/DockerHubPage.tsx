import React, { useState, useEffect } from 'react';
import { useLocation } from 'react-router-dom';
import { HardDrive, Container, Layers, Network, Database, Activity } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { HostProvider } from '@/features/devops/docker/context/HostContext';
import { DockerHostsPage } from '@/features/devops/docker/pages/DockerHostsPage';
import { DockerContainersPage } from '@/features/devops/docker/pages/DockerContainersPage';
import { DockerImagesPage } from '@/features/devops/docker/pages/DockerImagesPage';
import { DockerNetworksPage } from '@/features/devops/docker/pages/DockerNetworksPage';
import { DockerVolumesPage } from '@/features/devops/docker/pages/DockerVolumesPage';
import { DockerActivitiesPage } from '@/features/devops/docker/pages/DockerActivitiesPage';
import { DockerHealthPage } from '@/features/devops/docker/pages/DockerHealthPage';

const tabs = [
  { id: 'hosts', label: 'Hosts', icon: <HardDrive size={16} />, path: '/' },
  { id: 'containers', label: 'Containers', icon: <Container size={16} />, path: '/containers' },
  { id: 'images', label: 'Images', icon: <Layers size={16} />, path: '/images' },
  { id: 'networks', label: 'Networks', icon: <Network size={16} />, path: '/networks' },
  { id: 'volumes', label: 'Volumes', icon: <Database size={16} />, path: '/volumes' },
  { id: 'monitoring', label: 'Monitoring', icon: <Activity size={16} />, path: '/monitoring' },
];

export const DockerHubPage: React.FC = () => {
  const location = useLocation();

  const getActiveTab = () => {
    const path = location.pathname;
    if (path.includes('/docker/containers')) return 'containers';
    if (path.includes('/docker/images')) return 'images';
    if (path.includes('/docker/networks')) return 'networks';
    if (path.includes('/docker/volumes')) return 'volumes';
    if (path.includes('/docker/monitoring')) return 'monitoring';
    return 'hosts';
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
    if (activeTab === 'hosts') {
      base.push({ label: 'Docker' });
    } else {
      base.push({ label: 'Docker', href: '/app/devops/docker' });
      const activeTabInfo = tabs.find(t => t.id === activeTab);
      if (activeTabInfo) base.push({ label: activeTabInfo.label });
    }
    return base;
  };

  return (
    <HostProvider>
      <PageContainer
        title="Docker"
        description="Docker hosts, containers, images, and monitoring"
        breadcrumbs={getBreadcrumbs()}
      >
        <TabContainer
          tabs={tabs}
          activeTab={activeTab}
          onTabChange={setActiveTab}
          basePath="/app/devops/docker"
          variant="underline"
          className="mb-6"
        >
          <TabPanel tabId="hosts" activeTab={activeTab}>
            <DockerHostsPage />
          </TabPanel>
          <TabPanel tabId="containers" activeTab={activeTab}>
            <DockerContainersPage />
          </TabPanel>
          <TabPanel tabId="images" activeTab={activeTab}>
            <DockerImagesPage />
          </TabPanel>
          <TabPanel tabId="networks" activeTab={activeTab}>
            <DockerNetworksPage />
          </TabPanel>
          <TabPanel tabId="volumes" activeTab={activeTab}>
            <DockerVolumesPage />
          </TabPanel>
          <TabPanel tabId="monitoring" activeTab={activeTab}>
            <div className="space-y-8">
              <DockerActivitiesPage />
              <DockerHealthPage />
            </div>
          </TabPanel>
        </TabContainer>
      </PageContainer>
    </HostProvider>
  );
};

export default DockerHubPage;

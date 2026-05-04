import React, { useState, useEffect, useCallback } from 'react';
import { useLocation } from 'react-router-dom';
import { Boxes } from 'lucide-react';
import { PageContainer, type PageAction } from '@/shared/components/layout/PageContainer';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { KubernetesClustersPage } from '@/features/devops/kubernetes/pages/KubernetesClustersPage';

// Phase 2 v1 ships with a single tab. Phase 5 (worker sync job)
// adds Pods + Deployments tabs once we're pulling that state from
// the cluster API server.
const tabs = [
  { id: 'clusters', label: 'Clusters', icon: <Boxes size={16} />, path: '/' },
];

export const KubernetesHubPage: React.FC = () => {
  const location = useLocation();

  const getActiveTab = () => {
    // Default to clusters — only tab in v1.
    return 'clusters';
  };

  const [activeTab, setActiveTab] = useState(getActiveTab());
  const [actions, setActions] = useState<PageAction[]>([]);

  useEffect(() => {
    setActiveTab(getActiveTab());
  }, [location.pathname]);

  const handleActionsReady = useCallback((newActions: PageAction[]) => {
    setActions(newActions);
  }, []);

  return (
    <PageContainer
      title="Kubernetes"
      description="K3s and (Phase 3) kubeadm clusters managed by Powernode"
      actions={actions}
    >
      <TabContainer
        tabs={tabs}
        activeTab={activeTab}
        onTabChange={setActiveTab}
        basePath="/app/devops/kubernetes"
        variant="underline"
        className="mb-6"
      >
        <TabPanel tabId="clusters" activeTab={activeTab}>
          <KubernetesClustersPage onActionsReady={handleActionsReady} />
        </TabPanel>
      </TabContainer>
    </PageContainer>
  );
};

export default KubernetesHubPage;
